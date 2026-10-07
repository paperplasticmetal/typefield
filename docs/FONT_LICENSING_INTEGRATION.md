# Font activation and licensing integration

Updated 2026-10-07. User scope: direct foundry purchases, Adobe Fonts and Monotype, with personal or team coverage and a cost estimate.

## Shipped local capability

Typefield registers user-supplied local font files with Core Text for the current session and records ownership for cleanup. Library font actions and the font inspector expose activation/deactivation. Already system- or externally-activated fonts remain under their original owner. This is font availability, not a license purchase or entitlement check. Embedded license and vendor URLs are treated as external links, not proof of coverage.

## Remaining provider work

- **Monotype:** the documented enterprise integration requires a Monotype-issued application Client ID/secret, registered redirect URL, an onboarded organization/user and an administrator-issued access key. Its authorization-code flow is for confidential applications; secrets must remain on a backend, not in the macOS binary. The user confirmed that Typefield has no developer/partner access with these providers. Need a partner application and test organization before implementing and testing account linking, inventory, license coverage and any quote endpoint. [Enterprise integration](https://support.monotype.com/en/articles/8581921-enterprise-customers-api-integration-premium-fonts-inventory), [API authentication and security](https://support.monotype.com/en/articles/8805298-api-faqs).
- **Adobe Fonts:** the published Typekit API documents font metadata and web-kit operations. It does not document desktop entitlement/activation endpoints. Adobe's supported desktop activation flow uses the signed-in Creative Cloud account. Need Adobe confirmation of a supported third-party desktop integration before claiming account linking inside Typefield. [Published API](https://fonts.adobe.com/docs/api), [Desktop font activation](https://helpx.adobe.com/fonts/web/introduction/add-fonts-desktop.html).
- **Direct foundries:** download already-purchased files and add their folder for local activation today. Automated purchase history, organization seat assignment and prices need specific foundry partnerships/APIs and catalog identifiers. No provider or pricing contract has been supplied. A font's manufacturer/license metadata alone does not establish a price or entitlement.

## Integration acceptance criteria

Use provider-hosted authentication; keep backend secrets off the client and store user tokens in Keychain. Match exact product/style IDs, license use (desktop/web/app), account/organization and seat assignment. Show estimate currency, usage basis, source and retrieval date; distinguish quote from purchase. Handle expired, revoked, unavailable, unassigned and offline entitlements without treating unknown as licensed or free. Test with provider sandbox accounts and cancellation/revocation. Never extract or re-register protected subscription assets to bypass the provider's activation flow. No credentials, external purchases, license claims or mock estimates are shipped in 0.59.12.
