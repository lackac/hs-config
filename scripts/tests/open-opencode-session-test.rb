# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "rbconfig"
require_relative "../open-opencode-session"

class OpenCodeSessionLinkTest < Minitest::Test
  ID = "ses_Ab012"
  UUID = "086e2c22-1234-4444-abcd-001234567890"
  OTHER_UUID = "186e2c22-1234-4444-abcd-001234567890"
  SESSION = "session:#{UUID}"
  WINDOW = "window:#{UUID}"
  BLOCK = "block:#{UUID}"
  CLIENT = "client:#{UUID}"

  class StubOpener < SessionLinkOpener
    attr_reader :calls

    def initialize(*args, **options)
      super
      @calls = []
      @time = 0
    end

    def expect(*args, response:)
      (@commands ||= []) << [args, response]
    end

    def remaining_commands
      @commands || []
    end

    def advance(seconds)
      @time += seconds
    end

    private

    def rex_path
      "/Rex Server.app/rex"
    end

    def capture(command, *args, **options)
      if command == rex_path
        raise "Expected Rex to disable autostart and bound calls" unless args.shift(2) == ["--autostart=false", "--timeout"]
        args.shift
        command = "rex"
      end
      @calls << [[command, *args], options]
      expected, response = @commands&.shift
      raise "Expected #{expected.inspect}, got #{@calls.last.inspect}" unless [command, *args] == expected

      raise response if response.is_a?(Exception)
      response = response.call if response.is_a?(Proc)
      response.nil? ? nil : JSON.generate(response)
    end

    def now
      @time
    end

    def sleep(seconds)
      advance(seconds)
    end
  end

  def setup
    @tmp = Dir.mktmpdir("session-link-test")
    @saved_tmpdir, ENV["TMPDIR"] = ENV["TMPDIR"], @tmp
    @root = File.join(@tmp, "repo")
    @directory = File.join(@root, "subdir + &")
    FileUtils.mkdir_p(@directory)
    @root = File.realpath(@root)
    @directory = File.realpath(@directory)
    @opener = StubOpener.new(ID)
  end

  def teardown
    assert_empty @opener.remaining_commands
  ensure
    ENV["TMPDIR"] = @saved_tmpdir
    FileUtils.remove_entry(@tmp)
  end

  def client(id = CLIENT, transport: "unix", uid: Process.uid, state: "connected")
    { client_id: id, info: { kind: "app" }, principal: { kind: "peer", transport: transport, uid: uid }, connection_state: state }
  end

  def metadata(directory: @directory, canonical: @root, sandboxes: [])
    @opener.expect("opencode", "api", "get", "/api/session/#{ID}",
      response: { data: { id: ID, location: { directory: directory }, projectID: "project", subpath: "subdir + &" } })
    @opener.expect("opencode", "api", "get", "/api/project",
      response: [{ id: "other", canonical: "/other" }, { id: "project", canonical: canonical, sandboxes: sandboxes }])
  end

  def list(*clients)
    @opener.expect("rex", "client", "ls", "--json", response: { clients: clients })
  end

  def project(started:, block: BLOCK, root: @root)
    @opener.expect("rex", "do", "project_open_opencode", "path=#{root}", "directory=#{@directory}", "conversation=#{ID}", "--json",
      response: { session_id: SESSION, window_id: WINDOW, block_id: block, started: started })
  end

  def rpc(method, input, output)
    encoded = @directory.gsub(/[\/ +&]/, "/" => "%2F", " " => "+", "+" => "%2B", "&" => "%26")
    query = "location%5Bdirectory%5D=#{encoded}"
    @opener.expect("opencode", "api", "post", "/api/rpc/opencode.session-link/#{method}?#{query}",
      "--data", JSON.generate(input: input), response: output.is_a?(Hash) ? { output: output } : output)
  end

  def pending(acknowledged, request_id: UUID, session_id: ID)
    rpc("pending", { blockID: BLOCK }, { requestID: request_id, sessionID: session_id, acknowledged: acknowledged })
  end

  def request
    ready
    rpc("request", { sessionID: ID, blockID: BLOCK }, { requestID: UUID })
  end

  def ready
    pending(false, request_id: nil, session_id: nil)
  end

  def focus(response: {})
    @opener.expect("rex", "focus", "-s", SESSION, BLOCK, response: {})
    @opener.expect("rex", "-C", CLIENT, "do", "session.select", "session_id=#{SESSION}", "window_id=#{WINDOW}", response: response)
  end

  def test_dry_run_validates_id_and_does_not_contact_apps_or_create_lock
    opener = StubOpener.new(ID, dry_run: true)
    assert_output(/Would resolve #{ID}/) { opener.run }
    assert_empty opener.calls
    assert_empty Dir.glob(File.join(@tmp, "*.lock"))
    ["ses_/foo", "ses_#{'x' * 129}", "ses_abc\n", "--help", nil].each do |id|
      assert_raises(SessionLinkError) { StubOpener.new(id, dry_run: true).run }
    end
  end

  def test_cold_link_launches_in_background_and_waits_for_the_new_tui
    metadata
    @opener.expect("rex", "client", "ls", "--json", response: nil)
    @opener.expect("/usr/bin/open", "-g", "-a", "Rex", response: {})
    list(client(transport: "tcp"), client(uid: Process.uid + 1))
    list(client)
    project(started: true)
    rpc("pending", { blockID: BLOCK }, SessionLinkError.new("HTTP 400: RPC not registered"))
    rpc("pending", { blockID: BLOCK }, { acknowledged: false })
    request
    pending(false)
    pending(true)
    focus

    assert_output(/Opened #{ID}/) { @opener.run }
    assert_equal 1, @opener.calls.count { |args, _| args[3]&.include?("/request?") }
  end

  def test_warm_link_routes_external_sandbox_to_its_own_canonical_rex_root
    sandbox = File.join(@tmp, "worktree")
    @directory = File.join(sandbox, "nested")
    FileUtils.mkdir_p(@directory)
    @directory = File.realpath(@directory)
    symlink = File.join(@tmp, "repo link")
    File.symlink(@root, symlink)
    sandbox_link = File.join(@tmp, "worktree link")
    File.symlink(sandbox, sandbox_link)
    metadata(canonical: symlink, sandboxes: ["/no/longer/there", sandbox_link])
    list(client("client:#{OTHER_UUID}", transport: "tcp"), client)
    project(started: false, root: File.realpath(sandbox))
    request
    pending(true)
    focus

    assert_output(/Opened #{ID}/) { @opener.run }
    rex_calls = @opener.calls.select { |args, _| args.first == "rex" }
    rex_calls.each do |_, options|
      %w[XDG_RUNTIME_DIR REX_RUNTIME_DIR REX_HOME REX_SERVER REX_CLIENT REX_SESSION REX_BLOCK].each do |key|
        assert options[:env].key?(key)
        assert_nil options[:env][key]
      end
    end
    rpc_calls = @opener.calls.select { |args, _| args[0..2] == %w[opencode api post] }
    assert_equal [@directory, @directory, @directory], rpc_calls.map { |_, options| options[:chdir] }
  end

  def test_missing_session_stops_before_rex
    @opener.expect("opencode", "api", "get", "/api/session/#{ID}", response: { error: "not found" })
    assert_match(/did not return metadata/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_outside_project_stops_before_rex_even_when_path_has_same_prefix
    outside = File.join(@tmp, "repository")
    Dir.mkdir(outside)
    symlink = File.join(@root, "escape")
    File.symlink(outside, symlink)
    metadata(directory: symlink)
    assert_match(/outside its project/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_ambiguous_local_clients_stop_before_opening_a_project
    metadata
    list(client, client("client:#{OTHER_UUID}"))
    assert_match(/Multiple local.*Remote Control/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_project_lock_wait_is_bounded_before_rex
    metadata
    lock = File.join(@tmp, "opencode-session-link-#{Process.uid}-#{Digest::SHA256.hexdigest(@root)}.lock")
    File.open(lock, "w", 0o600) do |file|
      file.flock(File::LOCK_EX)
      assert_match(/Another session link/, assert_raises(SessionLinkError) { @opener.run }.message)
    end
  end

  def test_invalid_project_action_result_stops_before_rpc
    metadata
    list(client)
    project(started: true, block: "--unexpected")
    assert_match(/invalid OpenCode block target/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_rpc_preflight_timeout_preserves_last_error_without_sending_request
    metadata
    list(client)
    project(started: true)
    rpc("pending", { blockID: BLOCK }, SessionLinkError.new("HTTP 400: RPC not registered"))
    rpc("pending", { blockID: BLOCK }, -> {
      @opener.advance(15)
      raise SessionLinkError, "HTTP 400: plugin not loaded"
    })
    assert_match(/did not become ready.*plugin not loaded/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_request_failure_is_not_retried_and_does_not_focus
    metadata
    list(client)
    project(started: true)
    ready
    rpc("request", { sessionID: ID, blockID: BLOCK }, SessionLinkError.new("Lost connection"))
    assert_match(/delivery is uncertain.*Lost connection/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_missing_pending_entry_is_not_acknowledgement
    metadata
    list(client)
    project(started: false)
    request
    pending(false, request_id: nil, session_id: nil)
    assert_match(/lost or replaced/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_acknowledgement_for_another_request_is_not_success
    metadata
    list(client)
    project(started: false)
    request
    pending(true, request_id: OTHER_UUID)
    assert_match(/lost or replaced/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_accepted_but_unacknowledged_request_times_out
    metadata
    list(client)
    project(started: false)
    request
    rpc("pending", { blockID: BLOCK }, -> {
      @opener.advance(15)
      { output: { requestID: UUID, sessionID: ID, acknowledged: false } }
    })
    assert_match(/did not acknowledge/, assert_raises(SessionLinkError) { @opener.run }.message)
    refute @opener.calls.any? { |args, _| args[0..1] == %w[rex focus] }
  end

  def test_local_tab_selection_failure_suggests_remote_control
    metadata
    list(client)
    project(started: false)
    request
    pending(true)
    focus(response: SessionLinkError.new("permission denied"))
    assert_match(/Remote Control.*permission denied/, assert_raises(SessionLinkError) { @opener.run }.message)
  end

  def test_hung_command_is_killed_and_returns_a_bounded_error
    opener = SessionLinkOpener.new(ID)
    error = assert_raises(SessionLinkError) do
      opener.send(:capture, RbConfig.ruby, "-e", "sleep 60", timeout: 0.05)
    end
    assert_match(/timed out/, error.message)
  end
end
