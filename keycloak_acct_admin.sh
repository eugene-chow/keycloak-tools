#!/bin/bash
#
# The MIT License (MIT)
#
# Copyright (c) <year> <copyright holders>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE
#
# Author: Eugene Chow
# Description: Administer Keycloak accounts from the command-line
#
# ## Prerequisites
# In the Keycloak realm:
#   1) Create client (eg. keycloak_acct_admin) for this script
#   2) Add the realm admin user (eg. realm_admin) to the realm
#   3) In the realm admin user's settings > Client Role > "realm-management", assign it all available roles
#   4) In realm, enable Direct Grant API at Settings > Login


#### Config
# Change these parameters to suit your installation
base_url="https://key.cloak.url/auth"	#Keycloak base URL
realm="master"	#realm name
client_id="keycloak_acct_admin"	#create this client in the above Keycloak realm

#### Globals
refresh_token=""

#### Helpers
process_result() {
	expected_status="$1"
	result="$2"
	msg="$3"

	err_msg=${result% *}
	actual_status=${result##* }

	printf "[HTTP $actual_status] $msg "
	if [ "$actual_status" == "$expected_status" ]; then
		echo "successful"
		return 0
	else
		echo "failed"
		echo -e "\t$err_msg"
		return 1
	fi
}

kc_login() {
	read -p "Admin username: " admin_id
	read -s -p "Password: " admin_pwd; echo

	result=$(curl --write-out " %{http_code}" -s --request POST \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data "username=$admin_id&password=$admin_pwd&client_id=$client_id&grant_type=password" \
	"$base_url/realms/$realm/protocol/openid-connect/token")

	admin_pwd=""	#clear password
	msg="Login"
	process_result "200" "$result" "$msg"
	if [ $? -ne 0 ]; then
		echo "Please correct error before retrying. Exiting."
		exit 1	#no point continuing if login fails
	fi

	# Extract refresh_token
	refresh_token=$(sed -E -n 's/.*"refresh_token":"([^"]+)".*/\1/p' <<< "$result")
}

kc_create_user() {
	firstname="$1"
	lastname="$2"
	username="$3"
	email="$4"

	result=$(curl --write-out " %{http_code}" -s --request POST \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $refresh_token" \
	--data '{
		"enabled": "true",
		"username": "'"$username"'",
		"email": "'"$email"'",
		"firstName": "'"$firstname"'",
		"lastName": "'"$lastname"'"
	}' "$base_url/admin/realms/$realm/users")

	msg="$username: insert"
	process_result "201" "$result" "$msg"
	return $?	#return status from process_result
}

kc_delete_user() {
	username="$1"

	result=$(curl --write-out " %{http_code}" -s --request DELETE \
	--header "Authorization: Bearer $refresh_token" \
	"$base_url/admin/realms/$realm/users/$username")

	msg="$username: delete"
	process_result "204" "$result" "$msg"
	return $?	#return status from process_result
}

kc_set_pwd() {
	username="$1"
	password="$2"

	result=$(curl --write-out " %{http_code}" -s --request PUT \
	--header "Content-Type: application/json" \
	--header "Authorization: Bearer $refresh_token" \
	--data '{
		"temporary": "false",
		"type": "password",
		"value": "'"$password"'"
	}' "$base_url/admin/realms/$realm/users/$username/reset-password")

	msg="$username: password set"
	process_result "204" "$result" "$msg"
	return $?	#return status from process_result
}

kc_logout() {
	result=$(curl --write-out " %{http_code}" -s --request POST \
	--header "Content-Type: application/x-www-form-urlencoded" \
	--data "client_id=$client_id&refresh_token=$refresh_token" \
	"$base_url/realms/$realm/protocol/openid-connect/logout")

	msg="Logout"
	process_result "204" "$result" "$msg"	#print HTTP status message
	return $?	#return status from process_result
}

# Unit tests for helper functions
# Use this to check that the helper functions work
unit_test() {
	echo "Testing normal behaviour. These operations should succeed"
	kc_login
	kc_create_user john tan johntan john@tan.com
	kc_set_pwd johntan
	kc_delete_user johntan
	kc_logout

	echo "Testing abnormal behaviour. These operations should fail"
	kc_create_user john tan johntan john@tan.com	#try to create acct after logout
	kc_set_pwd johntan
	kc_delete_user johntan	#try to delete acct after logout
}

## Bulk import accounts
# Reads and creates accounts using a CSV file as the source
# CSV file format is assumed to be "first name, last name, username, email, password"
import_accts() {
	kc_login

	# Import accounts line-by-line
	while read -r line; do
		IFS=',' read -ra arr <<< "$line"
		kc_create_user "${arr[0]}" "${arr[1]}" "${arr[2]}" "${arr[3]}"
		[ $? -ne 0 ] || kc_set_pwd "${arr[2]}" "${arr[4]}"	#skip if kc_create_user failed
break
	done < "$csv_file"

	kc_logout
}

#### Main
if [ $# -lt 1 ]; then
	echo "Keycloak account admin script"
	echo "Usage: $0 [--test | --import csv_file]"
	exit 1
fi

flag=$1

case $flag in
	"--test" )
		unit_test
		;;
	"--import")
		csv_file="$2"
		if [ -z "$csv_file" ]; then
			echo "Error: missing 'csv_file' argument"
			exit 1
		fi
		import_accts $csv_file
		;;
	*)
		echo "Unrecognised flag '$flag'"
		exit 1
		;;
esac

exit 0
