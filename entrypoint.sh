#!/bin/sh -l

APP_ID=$1
BRANCH_NAME=$2
COMMIT_ID=$3
WAIT=$4
TIMEOUT=$5
NO_FAIL=$6
export AWS_DEFAULT_REGION="$AWS_REGION"

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  echo "You must provide the AWS_ACCESS_KEY_ID environment variable."
  exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  echo "You must provide the AWS_SECRET_ACCESS_KEY environment variable."
  exit 1
fi

if [[ -z "$AWS_DEFAULT_REGION" ]] ; then
  echo "You must provide the AWS_REGION environment variable."
  exit 1
fi

if [[ -z "$APP_ID" ]] ; then
  echo "You must provide the app-id."
  exit 1
fi

if [[ -z "$BRANCH_NAME" ]] ; then
  echo "You must provide the branch-name."
  exit 1
fi

if [[ -z "$COMMIT_ID" ]] ; then
  echo "You must provide the commit-id."
  exit 1
fi

if [[ $TIMEOUT -lt 0 ]]; then
    echo "Timeout must not be a negative number. Use 0 for unlimited timeout."
    exit 1
fi

get_status () {
    local status

    # Get the last job summary
    status=$(aws amplify list-jobs --app-id "$1" --branch-name "$2" | jq -r '.jobSummaries | first | .status')
    exit_status=$?

    # Remove any potential new lines from the status
    status=$(echo "$status" | tr -d '\n')

    echo "$status"
    return $exit_status
}

get_job_logs () {
    local job_id

    job_id=$(aws amplify list-jobs --app-id "$1" --branch-name "$2" | jq -r '.jobSummaries | first | .jobId')
    jobLogUrl=$(aws amplify get-job --job-id "$job_id" --app-id "$1" --branch-name "$2" | jq -r '.job .steps[0] .logUrl')

    return $jobLogUrl
}

no_fail_check () {
    if [[ $NO_FAIL == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

STATUS=$(get_status "$APP_ID" "$BRANCH_NAME" "$COMMIT_ID")

if [[ $? -ne 0 ]]; then
    echo "Failed to get status of the job."
    exit 1
fi

if [[ $STATUS == "SUCCEED" ]]; then
    echo "Build Succeeded!"
    job_logs=$(get_job_logs)
    echo "logs=$job_logs" >> $GITHUB_OUTPUT
    echo "status=$STATUS" >> $GITHUB_OUTPUT
    exit 0
elif [[ $STATUS == "FAILED" ]]; then
    echo "Build Failed!"
    echo "status=$STATUS" >> $GITHUB_OUTPUT
    no_fail_check
fi

count=0

if [[ -z $STATUS ]]; then
    echo "No job found for commit $COMMIT_ID. Waiting for job to start..."
    while [[ -z $STATUS ]]; do
        if [[ $count -ge 1800 ]]; then
            echo "Timed out waiting for job to start."
            exit 1
        fi
        sleep 30
        STATUS=$(get_status "$APP_ID" "$BRANCH_NAME" "$COMMIT_ID")
        if [[ $? -ne 0 ]]; then
            echo "Failed to get status of the job."
            exit 1
        fi
        count=$((count+30))
        echo "Waiting for job to start..."
    done
    elif [[ $STATUS ]]; then
        echo "Build in progress... Status: $STATUS"
    fi

seconds=$(( $TIMEOUT * 60 ))
count=0

if [[ "$WAIT" == "false" ]]; then
    echo "status=$STATUS" >> $GITHUB_OUTPUT
    exit 0
elif [[ "$WAIT" == "true" ]]; then
    while [[ $STATUS != "SUCCEED" ]]; do
        if [[ $TIMEOUT -ne 0 ]] && [[ $count -ge $seconds ]]; then
            echo "Timed out."
            exit 1
        fi
        sleep 30
        STATUS=$(get_status "$APP_ID" "$BRANCH_NAME" "$COMMIT_ID")
        if [[ $? -ne 0 ]]; then
            echo "Failed to get status of the job."
            exit 1
        fi
        if [[ $STATUS == "FAILED" ]]; then
            echo "Build Failed!"
            echo "status=$STATUS" >> $GITHUB_OUTPUT
            no_fail_check
        else
            echo "Build in progress... Status: $STATUS"
        fi
        count=$(( $count + 30 ))
    done
    job_logs=$(get_job_logs)
    echo "logs=$job_logs" >> $GITHUB_OUTPUT
    echo "Build Succeeded!"
    echo "status=$STATUS" >> $GITHUB_OUTPUT
fi
