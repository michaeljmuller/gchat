# Developer ID signing certificate

Releases of GChat for other people are signed with a Developer ID
Application certificate and notarized by Apple. Debug builds are signed with
the same certificate, so that the Keychain treats them as the same app as a
release; the reasoning is in the README under "Development workflow".

Current certificate: "Developer ID Application: Michael Muller (84URFQ3GPW)",
issued October 2, 2026 by the G2 authority, valid until September 17, 2031.
Apple's email of 2026 said G2 certificates expire yearly; the certificate
itself says 2031. Trust the certificate, and check its date with:

    security find-certificate -c "Developer ID Application: Michael Muller" -p \
        | openssl x509 -noout -enddate

Only the Apple developer account holder can create Developer ID
certificates.


## Why G2

Apple's original Developer ID authority expires on February 1, 2027.
Certificates it issued stop working that day. New certificates must come
from "Developer ID Certification Authority (G2)", valid until 2031. Apps
already signed and notarized with an old certificate keep working.

The account also has an older cloud-managed Developer ID Application
certificate that expires on February 1, 2027. Leave it to expire; do not
revoke it.


## Renewing by hand

1. Make a certificate signing request on the Mac that will sign releases.
   - Open Keychain Access.
   - Menu: Keychain Access > Certificate Assistant > Request a Certificate
     From a Certificate Authority.
   - User Email Address: the Apple developer account email.
   - Common Name: something recognizable, such as
     "Michael Muller Developer ID 2027".
   - Request is: Saved to disk. (With "Emailed to the CA" selected, the CA
     Email Address field becomes required; it is not needed when saving to
     disk.)
   - Save the .certSigningRequest file.
   This also creates the private key in the login keychain.

2. Create the certificate.
   - developer.apple.com > Account > Certificates, Identifiers & Profiles >
     Certificates > +.
   - Software: Developer ID > Developer ID Application.
   - Intermediary: G2 Sub-CA. The other choice issues a certificate from
     the expiring authority.
   - Upload the request file, then Download.

3. Install it by double-clicking the downloaded .cer file.

4. Check it is usable for signing:

       security find-identity -v -p codesigning

   It should list "Developer ID Application: Michael Muller (84URFQ3GPW)".

5. Back up the private key: Keychain Access > My Certificates, right-click
   the new certificate > Export, save as a password-protected .p12 kept
   outside this repository. Without it, a lost keychain means making a new
   certificate.

6. The first time codesign uses the new key, macOS asks for the login
   keychain password. Choose Always Allow; a release build signs several
   files and otherwise asks for each.


## To do (low priority): script the renewal

Apple's App Store Connect API can create certificates, so the steps above
can become one command:

- Generate the private key and signing request with openssl.
- Submit it with POST /v1/certificates, using an App Store Connect API key
  (created once under Users and Access > Integrations, kept out of the
  repository).
- Download the certificate and import it with the key into the login
  keychain (security import).
- Print the new expiry date.

To verify first: that the API offers a certificate type for the G2
authority (believed to be DEVELOPER_ID_APPLICATION_G2), and that API keys
are allowed to create Developer ID certificates.
