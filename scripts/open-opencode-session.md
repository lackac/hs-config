# OpenCode conversation links

`hammerspoon://opencode-session?id=ses_…` opens a local OpenCode V2
conversation in its Rex project. The helper reads the conversation's
directory and canonical project from the OpenCode API. It starts Rex in the
background if needed, then waits for the exact OpenCode block to acknowledge
the link before selecting the Rex tab and raising the app.

Enable **Remote Control** in **Rex → Settings → Rex Server** so the helper can
select that tab. Keep only one local Rex app client connected; remote app
clients aren't eligible. If an existing OpenCode TUI doesn't acknowledge a link
after you update the session-link plugin, run `/reload` in that TUI and retry.
The helper won't start another TUI when delivery is uncertain.

To preview without starting a service or changing app state, run
`ruby scripts/open-opencode-session.rb --dry-run ses_EXAMPLE`. This validates
the ID and prints the planned steps without looking up the conversation.

Run the stubbed tests with `ruby scripts/tests/open-opencode-session-test.rb`.
