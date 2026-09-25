# Community v2 API deployment

Copy the PHP endpoint into the same API directory as the existing mSign endpoints.

The endpoint is intentionally separate from the existing account/certificate code. Before enabling it, wire `community_auth()` to the same bearer-token/session validation already used by `account.php`.

Required database tables are documented in `schema.sql`.
