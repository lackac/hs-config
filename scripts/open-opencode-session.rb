#!/usr/bin/env -S ruby --disable-gems
# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "open3"
require "tmpdir"
require "uri"

class SessionLinkError < StandardError; end

class SessionLinkOpener
  UUID = /[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/i
  REX_ENV = %w[XDG_RUNTIME_DIR REX_RUNTIME_DIR REX_HOME REX_SERVER REX_CLIENT REX_SESSION REX_BLOCK].to_h { |key| [key, nil] }.freeze
  REMOTE_CONTROL = "Check Rex → Settings → Rex Server → Remote Control."
  RPC = "/api/rpc/opencode.session-link"

  def initialize(id, dry_run: false)
    raise SessionLinkError, "Invalid session ID." unless id&.match?(/\Ases_[A-Za-z0-9]{1,128}\z/)

    @id = id
    @dry_run = dry_run
  end

  def run
    # Even a GET via `opencode api` can start the background service.
    if @dry_run
      puts "Would resolve #{@id}, open its project in Rex, and focus the OpenCode block after it acknowledges the link."
      return
    end

    root, directory = project_location
    lock = File.join(Dir.tmpdir, "opencode-session-link-#{Process.uid}-#{Digest::SHA256.hexdigest(root)}.lock")
    File.open(lock, File::RDWR | File::CREAT | File::NOFOLLOW | File::NONBLOCK, 0o600) do |file|
      raise SessionLinkError, "Invalid project lock." unless file.stat.file? && file.stat.uid == Process.uid

      poll(20, "Another session link is still opening for this project.") do
        file.flock(File::LOCK_EX | File::LOCK_NB)
      end
      open_project(root, directory)
    end
  end

  private

  def project_location
    response = json("opencode", "api", "get", "/api/session/#{@id}")
    session = field(response, "data")
    project_id = field(session, "projectID")
    unless field(session, "id") == @id && project_id.is_a?(String) && !project_id.empty?
      raise SessionLinkError, "OpenCode did not return metadata for #{@id}."
    end
    directory = canonical_directory(field(field(session, "location"), "directory"), "session")

    projects = json("opencode", "api", "get", "/api/project")
    raise SessionLinkError, "Invalid OpenCode project list." unless projects.is_a?(Array)

    project = projects.find { |candidate| field(candidate, "id") == project_id }
    raise SessionLinkError, "OpenCode project for #{@id} was not found." unless project

    root = canonical_directory(project["canonical"], "project")
    sandboxes = project["sandboxes"]
    raise SessionLinkError, "Invalid OpenCode project sandboxes." unless sandboxes.is_a?(Array)

    unless inside?(directory, root) || inside_sandbox?(directory, sandboxes)
      raise SessionLinkError, "Session directory is outside its project and sandboxes."
    end
    [root, directory]
  end

  def canonical_directory(path, kind)
    if safe_path?(path)
      real = File.realpath(path)
      return real if safe_path?(real) && File.directory?(real)
    end
    raise SessionLinkError, "Invalid OpenCode #{kind} directory."
  rescue SystemCallError
    raise SessionLinkError, "OpenCode #{kind} directory is unavailable."
  end

  def inside_sandbox?(directory, sandboxes)
    sandboxes.any? do |path|
      inside?(directory, canonical_directory(path, "sandbox"))
    rescue SessionLinkError
      false # A recorded sandbox can have been removed.
    end
  end

  def safe_path?(path)
    path.is_a?(String) && path.start_with?("/") && path.bytesize <= 4096 && !path.match?(/[[:cntrl:]]/)
  end

  def inside?(directory, root)
    directory == root || directory.start_with?(root.end_with?("/") ? root : "#{root}/")
  end

  def open_project(root, directory)
    @rex = rex_path
    client = local_client
    unless client
      capture("/usr/bin/open", "-g", "-a", "Rex")
      client = poll(12, "No local Rex app client connected. #{REMOTE_CONTROL}") do |remaining|
        local_client(timeout: [2, remaining].min)
      end
    end

    output = rex("do", "project_open_opencode", "path=#{root}", "directory=#{directory}", "conversation=#{@id}", "--json")
    result = parse_json(output, "Rex project action")
    session, window, block, started = %w[session_id window_id block_id started].map { |key| field(result, key) }
    unless rex_id?(session, "session") && rex_id?(window, "window") && rex_id?(block, "block") && [true, false].include?(started)
      raise SessionLinkError, "Rex returned an invalid OpenCode block target."
    end

    switch_conversation(directory, block)
    rex("focus", "-s", session, block)
    begin
      rex("-C", client, "do", "session.select", "session_id=#{session}", "window_id=#{window}")
    rescue SessionLinkError => e
      raise SessionLinkError, "Could not select the tab in the local Rex app. #{REMOTE_CONTROL} #{e.message}"
    end
    puts "Opened #{@id} in Rex #{session} #{block}."
  end

  def rex_path
    candidates = [
      File.join(Dir.home, "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"),
      "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
    ]
    candidates.find { |path| File.file?(path) && File.executable?(path) } ||
      raise(SessionLinkError, "Could not find the CLI installed with Rex.app.")
  end

  def rex(*args, timeout: 10, allow_failure: false)
    capture(@rex, "--autostart=false", "--timeout", "#{[timeout, 8].min}s", *args,
      env: REX_ENV, timeout: timeout, allow_failure: allow_failure)
  end

  def local_client(timeout: 2)
    output = rex("client", "ls", "--json", timeout: timeout, allow_failure: true)
    return unless output

    clients = field(parse_json(output, "Rex client list"), "clients")
    raise SessionLinkError, "Invalid Rex client list. #{REMOTE_CONTROL}" unless clients.is_a?(Array)

    local = clients.select do |client|
      principal = field(client, "principal")
      uid = field(principal, "uid")
      field(field(client, "info"), "kind") == "app" &&
        field(client, "connection_state") == "connected" &&
        field(principal, "kind") == "peer" && field(principal, "transport") == "unix" &&
        (uid.nil? || uid == Process.uid)
    end
    raise SessionLinkError, "Multiple local Rex app clients are connected; cannot choose one. #{REMOTE_CONTROL}" if local.size > 1
    return if local.empty?

    id = field(local.first, "client_id")
    raise SessionLinkError, "Invalid local Rex app client ID. #{REMOTE_CONTROL}" unless rex_id?(id, "client")

    id
  end

  def switch_conversation(directory, block)
    timeout_message = "OpenCode did not acknowledge the conversation link; delivery is uncertain."
    deadline = now + 15
    request_id = field(rpc("request", directory, { sessionID: @id, blockID: block }, timeout: deadline - now), "requestID")
    unless request_id.is_a?(String) && request_id.match?(/\A#{UUID}\z/)
      raise SessionLinkError, "OpenCode returned an invalid request ID; delivery is uncertain."
    end

    wait_until(deadline, timeout_message) do |remaining|
      pending = rpc("pending", directory, { blockID: block }, timeout: remaining)
      acknowledged = field(pending, "acknowledged")
      unless field(pending, "requestID") == request_id && field(pending, "sessionID") == @id && [true, false].include?(acknowledged)
        raise SessionLinkError, "OpenCode lost or replaced the conversation request; delivery is uncertain."
      end
      acknowledged
    end
  end

  def rpc(method, directory, input, timeout:)
    query = URI.encode_www_form("location[directory]" => directory)
    response = json("opencode", "api", "post", "#{RPC}/#{method}?#{query}",
      "--data", JSON.generate(input: input), chdir: directory, timeout: timeout)
    field(response, "output")
  rescue SessionLinkError => e
    raise SessionLinkError, "OpenCode conversation #{method} failed; delivery is uncertain. #{e.message}"
  end

  def field(object, key)
    object[key] if object.is_a?(Hash)
  end

  def rex_id?(id, kind)
    id.is_a?(String) && id.match?(/\A#{kind}:#{UUID}\z/)
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def poll(seconds, message, &block)
    wait_until(now + seconds, message, &block)
  end

  def wait_until(deadline, message)
    while (remaining = deadline - now) > 0
      value = yield remaining
      return value if value && now < deadline

      remaining = deadline - now
      sleep [0.2, remaining].min if remaining > 0
    end
    raise SessionLinkError, message
  end

  def json(*args, **options)
    parse_json(capture(*args, **options), File.basename(args.first))
  end

  def parse_json(output, source)
    JSON.parse(output)
  rescue JSON::ParserError
    raise SessionLinkError, "#{source} returned invalid JSON."
  end

  def capture(*args, chdir: nil, timeout: 10, env: {}, allow_failure: false)
    user = Etc.getpwuid.name
    path = "/etc/profiles/per-user/#{user}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    deadline = now + timeout
    options = chdir ? { chdir: chdir } : {}
    Open3.popen3({ "PATH" => path }.merge(env), *args, pgroup: true, **options) do |stdin, stdout, stderr, child|
      stdin.close
      buffers = { stdout => +"", stderr => +"" }
      readers = buffers.keys
      bytes = 0
      begin
        until readers.empty?
          ready = IO.select(readers, nil, nil, [deadline - now, 0].max)
          break unless ready

          ready.first.each do |io|
            chunk = io.read_nonblock(16_384, exception: false)
            next if chunk == :wait_readable
            if chunk
              buffers[io] << chunk
              bytes += chunk.bytesize
              raise SessionLinkError, "#{File.basename(args.first)} returned too much output." if bytes > 8 * 1024 * 1024
            else
              readers.delete(io)
            end
          end
          break if now >= deadline
        end

        if readers.empty? && child.join([deadline - now, 0].max)
          return buffers[stdout] if child.value.success?
          return if allow_failure

          detail = buffers[stderr].strip.lines.first&.strip
          raise SessionLinkError, "#{File.basename(args.first)} failed#{detail && !detail.empty? ? ": #{detail[0, 240]}" : "."}"
        end
        return if allow_failure

        raise SessionLinkError, "#{File.basename(args.first)} timed out."
      ensure
        # Kill the command group even if the CLI exited but a child holds its pipes.
        if !readers.empty? || child.alive?
          begin
            Process.kill("KILL", -child.pid)
          rescue Errno::ESRCH
            nil
          end
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    dry_run = ARGV.delete("--dry-run")
    raise SessionLinkError, "Usage: open-opencode-session.rb [--dry-run] ses_ID" unless ARGV.size == 1

    SessionLinkOpener.new(ARGV.first, dry_run: !!dry_run).run
  rescue SessionLinkError, SystemCallError => e
    warn "OpenCode session link: #{e.message}"
    exit 1
  end
end
