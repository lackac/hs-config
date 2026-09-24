#!/usr/bin/env -S ruby --disable-gems
# frozen_string_literal: true

require "json"
require "open3"
require "digest"
require "tmpdir"

class SessionLinkError < StandardError; end

class SessionLinkOpener
  def initialize(id, dry_run: false)
    raise SessionLinkError, "Invalid session ID." unless id&.match?(/\Ases_[A-Za-z0-9]+\z/)

    @id = id
    @dry_run = dry_run
  end

  def run
    database = capture("opencode", "debug", "paths", "db").strip
    sql = <<~SQL
      SELECT s.directory, p.worktree AS project_root
      FROM session_v2 AS s JOIN project AS p ON p.id = s.project_id
      WHERE s.id = '#{@id}';
    SQL
    session = JSON.parse(capture("/usr/bin/sqlite3", "-readonly", "-json", database, sql)).first
    raise SessionLinkError, "Session not found." unless session

    root = File.realpath(session.fetch("project_root"))
    directory = File.realpath(session.fetch("directory"))
    raise SessionLinkError, "Session directory is outside its project." unless directory == root || directory.start_with?("#{root}/")

    lock = File.join(Dir.tmpdir, "opencode-session-link-#{Process.uid}-#{Digest::SHA256.hexdigest(root)}.lock")
    File.open(lock, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      open_project(root, directory)
    end
  end

  private

  def open_project(root, directory)
    name = project_session(root)
    started = false
    unless name
      if @dry_run
        puts "Would start project tmux session for #{root}."
        return
      end
      capture("sesh", "connect", "--switch", root)
      started = true
    end

    pane = nil
    window = nil
    if started
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
      loop do
        name = project_session(root)
        window = first_window(name) if name
        panes = window ? window_panes(window) : []
        pane = opencode_pane(panes)
        break if pane || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.2
      end
      raise SessionLinkError, "Project startup did not launch OpenCode in the first window." unless pane
    else
      window = first_window(name)
      panes = window_panes(window) if window
      pane = opencode_pane(panes) if panes
    end

    raise SessionLinkError, "Project tmux session has no first window." unless window

    unless pane
      active = panes.find { |_id, _command, selected, _mode| selected == "1" }
      if active && active[1].match?(/\A(?:zsh|bash|fish)\z/) && active[3] == "0" &&
         capture("tmux", "capture-pane", "-p", "-t", active[0]).rstrip.lines.last&.strip == "❯"
        pane = active
        launch = ["tmux", "send-keys", "-t", pane[0], "opencode", "Enter"]
      else
        launch = ["tmux", "split-window", "-d", "-t", window, "-c", directory, "-P", "-F", "#{'#{pane_id}'}", "exec opencode"]
      end
    end

    if @dry_run
      puts "Would select #{name} #{window} pane #{pane&.first || 'new'} and open #{@id}."
      return
    end

    unless pane
      pane = [capture(*launch).strip]
    else
      capture(*launch) if launch
    end
    capture("tmux", "select-window", "-t", window)
    capture("tmux", "select-pane", "-t", pane.first)

    payload = JSON.generate(input: { sessionID: @id, paneID: pane.first })
    output = capture("opencode", "api", "post", "/api/rpc/opencode.session-link/request", "--data", payload, chdir: root)
    raise SessionLinkError, "OpenCode did not accept the session request." unless JSON.parse(output).dig("output", "requestID")

    capture("tmux", "switch-client", "-t", name)
    puts "Opened #{@id} in #{name} #{pane.first}."
  end

  def project_session(root)
    capture("tmux", "list-sessions", "-F", "#{'#{session_id}'}|#{'#{session_path}'}", allow_failure: true).lines.filter_map do |line|
      candidate, path = line.strip.split("|", 2)
      candidate if path && File.exist?(path) && File.realpath(path) == root
    end.first
  end

  def first_window(name)
    capture("tmux", "list-windows", "-t", name, "-F", "#{'#{window_index}'}|#{'#{window_id}'}", allow_failure: true)
      .lines.map { |line| line.strip.split("|", 2) }.min_by { |index, _id| index.to_i }&.last
  end

  def window_panes(window)
    capture("tmux", "list-panes", "-t", window, "-F", "#{'#{pane_id}'}|#{'#{pane_current_command}'}|#{'#{pane_active}'}|#{'#{pane_in_mode}'}")
      .lines.map { |line| line.strip.split("|") }
  end

  def opencode_pane(panes)
    panes.find { |id, _command, _active, _mode| option(id) == "1" } ||
      panes.find { |_id, command, _active, _mode| command.match?(/opencode/) }
  end

  def option(id)
    capture("tmux", "show-options", "-p", "-v", "-t", id, "@opencode-tui", allow_failure: true).strip
  end

  def capture(*args, chdir: nil, allow_failure: false)
    env = { "PATH" => "/etc/profiles/per-user/#{ENV.fetch('USER')}/bin:/run/current-system/sw/bin:/usr/bin:/bin" }
    output, error, status = Open3.capture3(env, *args, **(chdir ? { chdir: chdir } : {}))
    raise SessionLinkError, "#{args.first} failed: #{error.strip}" if !status.success? && !allow_failure

    output
  end
end

begin
  dry_run = ARGV.delete("--dry-run")
  SessionLinkOpener.new(ARGV.fetch(0), dry_run: !!dry_run).run
rescue SessionLinkError, KeyError, Errno::ENOENT, JSON::ParserError => e
  warn "OpenCode session link: #{e.message}"
  exit 1
end
