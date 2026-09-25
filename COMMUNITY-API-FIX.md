# mSign MDID + Community API routing fix

The account MDID mutation and community requests now use the deployed
`https://apii.zefv.dev/Msign-api/api/` endpoints instead of the root PHP router.

- Login/register remain on the root API (`login.php`, `register.php`).
- Authenticated account profile + admin MDID mutation use `/Msign-api/api/account.php`.
- Community members/messages/conversations/friends/profile/certificate requests use `/Msign-api/api/*.php`.
- Community requests include the session token in the query/body as a fallback for Apache deployments that do not populate `HTTP_AUTHORIZATION`.
