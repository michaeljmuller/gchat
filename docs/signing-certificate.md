# Developer ID signing certificate

The certificate that signs GChat, and how to renew it, for the Apple
developer account holder. Why Debug builds use the same certificate is in
design.md.

GChat releases and Debug builds are signed with a Developer ID Application
certificate. Apple also notarizes releases.

The current certificate is "Developer ID Application: Michael Muller
(84URFQ3GPW)". The G2 authority issued it on October 2, 2026, and it is
valid until September 17, 2031. To show the end date:

    security find-certificate -c "Developer ID Application: Michael Muller" -p \
        | openssl x509 -noout -enddate

Apple's email of 2026 said that certificates from G2 expire after one year.
The certificate itself shows 2031. The date in the certificate is the one
that applies.

Only the account holder can make Developer ID certificates.


## Why G2

The original Developer ID authority of Apple expires on February 1, 2027.
Certificates that it issued stop working that day. New certificates must come
from "Developer ID Certification Authority (G2)", which is valid until 2031.
Apps that were signed and notarized before February 1, 2027, continue to
work.

The account also has an older Developer ID Application certificate that Apple
manages in the cloud. It expires on February 1, 2027. Let it expire. Do not
revoke it, because a revoked certificate can stop apps that it signed.


## When the certificate expires

Copies that were signed and notarized while the certificate was valid
continue to run. A new release needs a valid certificate. A release signed
with a renewed certificate has the same team and bundle ID, so macOS treats
it as the same app.

Not verified yet: that the Keychain gives access to a release signed with a
renewed certificate without a prompt.


## Renew the certificate

To renew the certificate, the account holder does these steps on the Mac
that signs releases:

1. Open Keychain Access.
2. Click Keychain Access > Certificate Assistant > Request a Certificate From
   a Certificate Authority.
3. In User Email Address, type the email address of the Apple developer
   account.
4. In Common Name, type a name that identifies the certificate, for example
   "Michael Muller Developer ID 2031".
5. For Request is, select Saved to disk. With "Emailed to the CA" selected,
   the CA Email Address field becomes required.
6. Save the .certSigningRequest file. This step also makes the private key in
   the login Keychain.
7. Go to developer.apple.com > Account > Certificates, Identifiers & Profiles
   > Certificates, and click +.
8. Select Developer ID, then Developer ID Application.
9. For the intermediary, select G2 Sub-CA.
10. Upload the .certSigningRequest file, then click Download.
11. Double-click the downloaded .cer file to install it.
12. Make sure that the certificate can sign:

        security find-identity -v -p codesigning

    The list must contain "Developer ID Application: Michael Muller
    (84URFQ3GPW)".
13. Export a backup of the private key: in Keychain Access, open My
    Certificates, right-click the new certificate, click Export, and save a
    .p12 file with a password. Keep it outside the repository. Without the
    backup, a lost Keychain means a new certificate.

At the first signing with the new key, macOS asks for the password of the
login Keychain. Click Always Allow. A build signs several files and asks for
each one otherwise.
