#!/bin/bash
####################################################################################################################

####################################################################################################################
# General
####################################################################################################################
OAUTH_GRANT_TYPE="client_credentials"

DEFAULT_NUM_OF_RETRIES="3"
DEFAULT_RETRY_DELAY_SECS="5"

# Currently headers cannot have spaces!
HEADER_CONTENT_TYPE_JSON="Content-Type:application/json"
HEADER_AP_ENV_ID="X-ANYPNT-ENV-ID:"
HEADER_AP_ORG_ID="X-ANYPNT-ORG-ID:"

LOCAL_FIELD_SEP=":"

ERROR_RESPONSES="null Unauthorized"
JSON_ERROR_PATHS=".error"
####################################################################################################################

####################################################################################################################
# build_http_headers
####################################################################################################################
build_http_headers() {
    name=$1[@]
    headers_local=("${!name}")
    concatHeaders=""
    for header in "${headers_local[@]}" 
    do
        if [ ! -z "${header}" ]
        then
            concatHeaders+=" --header ${header}"
        fi
    done
    echo "${concatHeaders}"
}
####################################################################################################################

####################################################################################################################
# body_http_request
####################################################################################################################
body_http_request() {
    method="${1}"
    url="${2}"
    data="${3}"
    headers_ref="${4}"
    
    retry_num="${DEFAULT_NUM_OF_RETRIES}"
    retry_delay_secs="${DEFAULT_RETRY_DELAY_SECS}"

    http_headers=$(build_http_headers "${headers_ref}")

    response=$(curl -s --retry "${retry_num}" --retry-connrefused --retry-delay "${retry_delay_secs}" --location \
     ${http_headers} --request "${method}" --data "${data}" --url "${url}")

     echo "${response}"
}
####################################################################################################################

####################################################################################################################
# body_http_request
####################################################################################################################
auth_body_http_request() {
    method="${1}"
    url="${2}"
    data="${3}"
    headers_ref="${4}"
    token="${5}"
    
    retry_num="${DEFAULT_NUM_OF_RETRIES}"
    retry_delay_secs="${DEFAULT_RETRY_DELAY_SECS}"

    http_headers=$(build_http_headers "${headers_ref}")

    response=$(curl -s --retry "${retry_num}" --retry-connrefused --retry-delay "${retry_delay_secs}" --location \
     ${http_headers} --oauth2-bearer "${token}" --request "${method}" --data "${data}" --url "${url}")

     echo "${response}"
}
####################################################################################################################

####################################################################################################################
#nobody_http_request
####################################################################################################################
nobody_http_request() {
    method="${1}"
    url="${2}"
    token="${3}"
    headers_ref="${4}"
    
    retry_num="${DEFAULT_NUM_OF_RETRIES}"
    retry_delay_secs="${DEFAULT_RETRY_DELAY_SECS}"

    http_headers=$(build_http_headers "${headers_ref}")

    response=$(curl -s --retry "${retry_num}" --retry-connrefused --retry-delay "${retry_delay_secs}" --location \
     ${http_headers} --oauth2-bearer "${token}" --request "${method}" --url "${url}")

     echo "${response}"
}
####################################################################################################################

####################################################################################################################
# http_request
####################################################################################################################
http_request() {
    method="${1}"
    url="${2}"
    headers_ref="${3}"
    data="${4:-null}"
    token=${5:-null}
    
    if [ "${method}" == "POST" -o "${method}" == "PUT" ]
    then
        if [ "${token}" == "null" ]
        then
            body_http_request "${method}" "${url}" "${data}" "${headers_ref}"
        else
            auth_body_http_request "${method}" "${url}" "${data}" "${headers_ref}" "${token}"
        fi
    elif [ "${method}" == "GET" ]
    then
        nobody_http_request "${method}" "${url}" "${token}" "${headers_ref}"
    else
        echo "ERROR: method not implmented: [${method}]"
    fi

}
####################################################################################################################

####################################################################################################################
# json_query
####################################################################################################################
json_query() {
    echo "${1}" | jq "${2}" | tr -d '"'
}
####################################################################################################################

####################################################################################################################
# get_delimited_field
####################################################################################################################
get_delimited_field() {
    str="${1}"
    field_num="${2}"
    sep="${3:-${LOCAL_FIELD_SEP}}"

    echo "${str}" | cut -f"${field_num}" -d"${sep}"
}
####################################################################################################################

####################################################################################################################
# convert_delimiter
####################################################################################################################
convert_delimiter() {
    str="${1}"
    input_delim="${2}"
    output_delim="${3}"

    echo "${str}" | sed 's/'"${input_delim}"'/'"${output_delim}"'/g'
}
####################################################################################################################

####################################################################################################################
# validate_error_response
####################################################################################################################
validate_error_response() {
    response="${1}"
    msg="${2}"

    error_msg="ERROR: ${msg}"
    for error in ${ERROR_RESPONSES[@]}
    do
        if [ "${response}" == "${error}" ]
        then
            echo "${error_msg}. Response contains error: [${error}]. Exiting 1."
            exit 1
        fi
    done

    for json_error in ${JSON_ERROR_PATHS[@]}
    do
        error=$(json_query "${response}" "${json_error}")
        if [ ! -z "${error}" -a "${error}" != "null" ]
        then
            echo "${error_msg}. Response contains a json error: [${error}]. Exiting 1."
            exit 1
        fi
    done
}
####################################################################################################################

####################################################################################################################
# client_credentials_login
####################################################################################################################
client_credentials_login() {
    local_client_id="${1}"
    local_client_secret="${2}"

    echo "INFO: Retrieving oauth token!"
    url="https://anypoint.mulesoft.com/accounts/api/v2/oauth2/token"
    headers=("${HEADER_CONTENT_TYPE_JSON}")
    request_body='{"client_id" : "'"${local_client_id}"'", "client_secret": "'"${local_client_secret}"'", "grant_type" : "'"${OAUTH_GRANT_TYPE}"'"}'
    oauth_response=$(http_request "POST" "${url}" "headers" "${request_body}" "null")
    validate_error_response "${oauth_response}" "Call oauth login with client id and secret"
    
    oauth_token=$(json_query "${oauth_response}" ".access_token")
}
####################################################################################################################

####################################################################################################################
# retrieve_org_id
####################################################################################################################
retrieve_org_id() {
    local_oauth_token="${1}"
    local_org_id="${2}"

    echo "INFO: Retrieving org id!"
    url="https://anypoint.mulesoft.com/accounts/api/me"
    headers=("${HEADER_CONTENT_TYPE_JSON}")

    orgid_response=$(http_request "GET" "${url}" "headers" "null" "${local_oauth_token}")
    validate_error_response "${orgid_response}" "Call to retrieve org id"

    org_id=$(json_query "${orgid_response}" ".user.organization.id")
    org_name=$(json_query "${orgid_response}" ".user.organization.name")

    echo "INFO: Org id: [${org_id}] name: [${org_name}]"
    if [ "${local_org_id}" != "${org_id}" ]
    then
        echo "ERROR: Argument org id is different from the APIs"
        exit 1
    fi
}
####################################################################################################################

####################################################################################################################
# retrieve_envs
####################################################################################################################
retrieve_envs() {
    local_oauth_token="${1}"
    local_org_id="${2}"

    echo "INFO: Retrieving list of environments for org: [${local_org_id}]!"
    url="https://anypoint.mulesoft.com/accounts/api/organizations/${local_org_id}/environments"
    list_env_response=$(http_request "GET" "${url}" "headers" "null" "${local_oauth_token}")
    validate_error_response "${list_env_response}" "Call to retrieve list of environments"

    echo "INFO: Environments for Business Group"
    list_env=$(echo "${list_env_response}" | jq ".data | .[] | {id: .id, name: .name, type: .type}")
    echo "${list_env}"
}
####################################################################################################################

####################################################################################################################
# get_selected_envs
####################################################################################################################
get_selected_envs() {
    local_oauth_token="${1}"
    shift
    local_org_id="${1}"
    shift

    local_req_envs=("${@}")

    retrieve_envs "${local_oauth_token}" "${local_org_id}"
    unset selected_envs
    i=0
    for env in "${local_req_envs[@]}"
    do
        env_detail=$(echo "${list_env}" | jq --arg ENV_NAME "${env}" 'select(.name == $ENV_NAME)')
        if [ ! -z "${env_detail}" ]
        then 
            env_id=$(json_query "${env_detail}" ".id")
            env_name=$(json_query "${env_detail}" ".name")
            selected_envs[${i}]="${env_name}${LOCAL_FIELD_SEP}${env_id}"
            i=$(expr $i + 1)
        else
            echo "WARN: Env: [${env}] does not exist" 
        fi
    done
}
####################################################################################################################

####################################################################################################################
# retreieve_applications_for_env
####################################################################################################################
retrieve_applications_for_env() {
    local_oauth_token="${1}"
    local_env_id="${2}"

    headers=("${HEADER_CONTENT_TYPE_JSON}" "${HEADER_AP_ENV_ID}${local_env_id}")

    echo "INFO: Retrieving applications for environment: [${local_env_id}]!"
    url="https://anypoint.mulesoft.com/cloudhub/api/v2/applications"
    applications_response=$(http_request "GET" "${url}" "headers" "null" "${oauth_token}")
}
####################################################################################################################

####################################################################################################################
# get_selected_applications_for_env
####################################################################################################################
get_selected_applications_for_env() {
    local_oauth_token="${1}"
    shift
    local_select_env_id="${1}"
    shift

    local_selected_app=("${@}")

    retrieve_applications_for_env "${local_oauth_token}" "${local_select_env_id}"
    if [ -z "${applications_response}" ] 
    then
        echo "WARN: no applications deployed to environment: [${local_select_env_id}]"
        return
    fi

    unset applications_deployed
    i=0
    for app in "${local_selected_app[@]}"
    do
        application_detail=$(echo "${applications_response}" | jq --arg APP_NAME "${app}" '.[] | select(.domain == $APP_NAME) | {domain: .domain, status: .status, region: .region, filename: .fileName, loggingCustomLog4JEnabled: .loggingCustomLog4JEnabled}')
        if [ ! -z "${application_detail}" ]
        then
            echo "INFO: Details for application: [${app}]"
            echo "${application_detail}"

            app_name="$(json_query "${application_detail}" ".domain")"
            log4jCustom="$(json_query "${application_detail}" ".loggingCustomLog4JEnabled")"
            applications_deployed[${i}]="${app_name}${LOCAL_FIELD_SEP}${log4jCustom}"
            i=$(expr $i + 1)
        fi
    done
}
####################################################################################################################

####################################################################################################################
# update_application
####################################################################################################################
update_application() {
    local_oauth_token="${1}"
    local_org_id="${2}"
    local_env_id="${3}"
    local_app_name="${4}"

    echo "INFO: Enabling [loggingCustomLog4JEnabled] for application: [${local_app_name}]"
    url="https://anypoint.mulesoft.com/cloudhub/api/v2/applications/${local_app_name}"
    headers=("${HEADER_CONTENT_TYPE_JSON}" "${HEADER_AP_ENV_ID}${env_id}" "${HEADER_AP_ORG_ID}${org_id}")
    request_body='{"loggingCustomLog4JEnabled":"true"}'
    update_status_response=$(http_request "PUT" "${url}" "headers" "${request_body}" "${oauth_token}")

    validate_error_response "${update_status_response}" "Call update application: [loggingCustomLog4JEnabled]:[true]"
    echo "${update_status_response}" | jq "{domain: .domain, status: .status, region: .region, filename: .fileName, loggingCustomLog4JEnabled: .loggingCustomLog4JEnabled}"
}
####################################################################################################################

####################################################################################################################
# update_selected_applications_for_envs
####################################################################################################################
update_selected_applications_for_envs() {
    local_oauth_token="${1}"
    shift
    local_org_id="${1}"
    shift
    local_selected_env_ref="${1}"
    shift

    name_ref=${local_selected_env_ref}[@]
    local_selected_env=("${!name_ref}")

    local_selected_apps=("${@}")

    for env in "${local_selected_env[@]}"
    do
        env_name=$(get_delimited_field "${env}" "1")
        env_id=$(get_delimited_field "${env}" "2")
        
        echo "INFO: Env - Name: [${env_name}] - Id: [${env_id}]"        
        get_selected_applications_for_env "${local_oauth_token}" "${env_id}" "${local_selected_apps[@]}"
        if [ "${#applications_deployed[@]}" -eq 0 ]
        then
            echo "INFO: No application for environment: [${env_name}]"
            continue
        fi

        echo "INFO: Number of applications: ${#applications_deployed[@]}"
        for app_deploy in "${applications_deployed[@]}"
        do
            app_name=$(get_delimited_field "${app_deploy}" "1")
            app_cust_log4j_enabled=$(get_delimited_field "${app_deploy}" "2")

            if [ "${app_cust_log4j_enabled}" == "false" ]
            then
                update_application "${local_oauth_token}" "${local_org_id}" "${env_id}" "${app_name}"
            else
                echo "INFO: Application: [${app_name}] already have custom log4j enabled: [${app_cust_log4j_enabled}]"
            fi
        done
    done
}
####################################################################################################################

####################################################################################################################
# usage
####################################################################################################################
usage() {
  cat <<-EOF
  Usage: $0 <client_id> <client_secret> <org id> <csv environments> <csv applications>
  Options:
    -h, --help           Show this help
    -c, --client-id      Client id used to authenticate with CloudHub
    -s, --client-secret  Client secret used to authenticate with CloudHub
    -o, --org-id         CloudHub organization id
    -e, --envs           Environments to check for applications
    -a, --apps           Applications to enable custom logging   
  Where:
    CSV environment names without spaces. e.g. env,env1,env2
    CSV application names without spaces. e.g. app,app1,app2
EOF
}
####################################################################################################################

####################################################################################################################
# parse_args
####################################################################################################################
parse_args() {
    while test ${#} -ne 0; do
        arg=${1}; shift
        case "${arg}" in
            -h|--help) usage; exit 1;;
            -c|--client-id) arg_client_id="${1}"; shift;;
            -s|--client-secret) arg_client_secret="${1}"; shift;;
            -o|--org-id) arg_org_id="${1}"; shift;;
            -e|--envs) arg_envs="${1}"; shift;;
            -a|--apps) arg_applications="${1}"; shift;;
        esac
    done

    if [ "${arg_client_id:-null}" == "null" -o "${arg_client_secret:-null}" == "null" -o "${arg_org_id:-null}" == "null" -o "${arg_envs:-null}" == "null" -o "${arg_applications:-null}" == "null" ]
    then
        usage
        exit 1
    fi
}
####################################################################################################################

####################################################################################################################
# Main
####################################################################################################################
parse_args "${@}"

envs_arr=($(convert_delimiter "${arg_envs}" "," " "))
applications_arr=($(convert_delimiter "${arg_applications}" "," " "))

#Sets global oauth_token
client_credentials_login "${arg_client_id}" "${arg_client_secret}"

# Sets global:
#   org_id
#   org_name
retrieve_org_id "${oauth_token}" "${arg_org_id}"

# Sets global:
#   selected_envs
get_selected_envs "${oauth_token}" "${org_id}" "${envs_arr[@]}"

# "selected_envs" is passed as reference
update_selected_applications_for_envs "${oauth_token}" "${org_id}" "selected_envs" "${applications_arr[@]}"

echo "INFO: Finished"