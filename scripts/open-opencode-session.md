# OpenCode conversation links

`hammerspoon://opencode-session?id=ses_…` opens a local OpenCode V2
conversation in its Rex project. The helper reads the conversation's
directory and canonical project from the OpenCode API. An external registered
sandbox uses its own checkout as the Rex project root. The helper starts Rex
in the background if needed, waits for OpenCode's location RPC to become
available, and sends one navigation request. It selects the tab and raises Rex
only after the exact OpenCode block acknowledges the link.

After updating the Rex project action and OpenCode session-link plugin, choose
**Reload Config** in the Hammerspoon menu. Enable **Remote Control** in
**Rex → Settings → Rex Server** so the helper can select the tab. Keep only
one local Rex app client connected; remote app clients aren't eligible.
Run `/reload` in existing OpenCode TUIs so they use the updated plugin.
The helper won't start another TUI when delivery is uncertain.

To preview without starting a service or changing app state, run
`ruby scripts/open-opencode-session.rb --dry-run ses_EXAMPLE`. This validates
the ID and prints the planned steps without looking up the conversation.

Run the stubbed tests with `ruby scripts/tests/open-opencode-session-test.rb`.
