# <Ticket-ID>: test cases

Use BDD-style Given/When/Then format.  Focus on observable
behaviour from the user's perspective, not on internal
implementation details.

Each scenario should name its implementation: either the
automated test that covers it, or `manual` with a one-line note
on how it's verified.  A scenario without an implementation is a
TODO, not a shipped behaviour.

---

**Given** <precondition>,
**when** <action>,
**then** <expected outcome>.

*Test:* `path/to/test_file.py::test_function_name`

**Given** <error precondition>,
**when** <action>,
**then** <expected graceful behaviour>.

*Test:* `path/to/test_file.py::test_error_path`

**Given** <ui precondition>,
**when** <user action>,
**then** <visible result>.

*Test:* manual — verified by ops during weekly sweep using
`<test plan or runbook link>`.
