# Security Policy

## Supported versions

Only the latest release of Hwaro receives security fixes. Upgrade to it
before reporting, and check whether the issue still reproduces there.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub: open the repository's
**Security** tab, choose **Advisories**, then **Report a vulnerability**.
Please do not open a public issue, pull request or discussion for a
security problem.

Include the Hwaro version (`hwaro version`), the command you ran, and a
minimal site or input that reproduces the issue.

## Trust model

Hwaro treats `config.toml` (and `config.<env>.toml`) and templates as
trusted: they belong to the site owner, and their commands, paths and
template code run with the owner's authority. Content, front matter,
imported sites and remote data are untrusted: they must not be able to
escape the project directory, inject markup or script beyond what the
site's own Markdown settings allow, or crash the build. A report that
untrusted input can do any of these is in scope; a report that requires
editing `config.toml` or a template generally is not.
