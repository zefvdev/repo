# mSign Community v2

This package adds the client-side Community v2 surfaces:

- Members and public profiles
- Direct messages + New Message
- Announcements
- Staff announcements with audience targeting
- Staff messages
- Developer/Admin staff gate
- Audit log client
- Existing certificate request flow remains intact

## API contract

The new client expects:

`community.php?action=announcements`
`community.php?action=audit`
`POST community.php {action:announcement_read,announcement_id}`
`POST community.php {action:announcement_create,title,body,audience,target?,expires_at?}`

Existing endpoints remain:

`members.php`
`conversations.php`
`messages.php`
`certificate_requests.php`
`profile.php`
`friends.php`

The server must enforce authorization. The Swift UI is not a security boundary.

Announcement audience values:

- `everyone`
- `staff`
- `developer`
- `admin`
- `individual`

For `individual`, the server resolves the target username to a user ID and stores the target. It should also write an audit event containing actor, role, action, target and timestamp.
