# mSign Community + Managed Certificates

This build adds the planned account/community layer:

- **Profiles:** the signed-in account has a public profile and MDID association.
- **Members:** searchable/listable member profiles with role/badge information and a direct Message action.
- **Messaging:** account-to-account conversations with unread counts and server-side authorization.
- **Certificate requests:** users submit certificate type, UDID, **Why do you need a certificate?**, and **How will this benefit mSign?**.
- **Request status:** Pending, Reviewing, Approved, Denied, or Completed, with optional staff response.
- **Managed certificates:** an approved certificate is attached to the user's MDID. The client receives metadata only; it does not receive a P12/private key or password.
- **Non-exportable signing model:** signing material must remain inside the trusted signing service. The app never exposes a certificate export/download path.
- **Staff workflow:** staff can review requests, communicate with the requester, approve/deny/request more information, and associate/replace a managed certificate through the server-side certificate workflow.

## API contract expected by the app

The existing account API base (`https://apii.zefv.dev/`, configurable with `uzd_account_base`) is used for:

- `members.php`
- `profile.php` (reserved for expanded profile editing)
- `conversations.php`
- `messages.php`
- `certificate_requests.php`

All authenticated calls use the existing session token plus the existing `X-OTA-Token` transport header.

### Certificate security requirement

The API must never return the raw `.p12`, private key, or P12 password to a member client. A signing worker should resolve the authenticated user's MDID, authorize the certificate association, retrieve the encrypted signing material internally, perform the signing operation, and return only the signed artifact/result.

The server should encrypt signing material at rest, restrict access to the signing worker, avoid logging secrets, and audit attachment/replacement/revocation and signing events.

## Request payload

`POST certificate_requests.php` with:

```json
{
  "action": "create",
  "certificate_type": "Development",
  "reason": "...",
  "udid": "...",
  "benefit": "...",
  "mdid": "MS-XXXXXX-XX"
}
```

## Profile UI update
- Account settings now include a persistent `Show profile customization` toggle. When enabled, the Username Style editor and all account-management cards below it are shown; disabling it collapses those sections.
- Community member profiles now show profile views, friend count, signing count, public username style, a Message button, and Add Friend action.
- Profile view and friend actions use `profile.php` and `friends.php` server contracts and are authorized by the VPS API.
