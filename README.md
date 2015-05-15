# keycloak-tools

Tools to manage a Keycloak SSO installation.

## keycloak_acct_admin.sh
A BASH script that connects to Keycloak's REST endpoints. It is able to:
- Login/Logout
- Create/Delete account
- Set account password

If you need to extend its functionality, you can:
- Read Keycloak's REST API at http://keycloak.jboss.org/docs/
- Inspect the HTTP packets exchanged between Keycloak's admin console and the server
	- In Chrome, click on the menu button, and then "More Tools > Developer Tools > Network"
	- In Firefox, click on the menu button, and then "Developer > Network"

A big thank you to the Keycloak team, especially Marek for helping me figure this out. Good luck!
