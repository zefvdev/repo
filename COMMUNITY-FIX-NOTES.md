# Community / Certificate fix

This revision fixes the three reported Community problems:

- Request Certificate now has a visible Back button.
- Certificate submission sends the authenticated session token in both the request body and query string, validates application-level PHP failures, refreshes request status, and shows a submitted confirmation.
- Members and Messages refresh independently so one failing endpoint no longer prevents the other screens from loading.
- PHP/MySQL numeric IDs are accepted instead of being silently discarded by the Swift parser.
- API response fields support the existing top-level response and a `data` wrapper.
- Members and Messages now show explicit loading/empty states.
- The Community header no longer overlaps `MSIGN COMMUNITY` and the screen title.
- Request Certificate displays the current MDID and can reuse a saved device UDID.
