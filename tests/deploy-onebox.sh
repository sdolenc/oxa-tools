#!/usr/bin/env bash
# Licensed under the MIT license. See LICENSE file on the project webpage for details.

set -eo pipefail

# Determine the appropriate github branch to clone.
get_branch()
{
    local branchInfo=

    if [[ -n $CIRCLE_BRANCH ]] ; then
        branchInfo=$CIRCLE_BRANCH
    elif [[ -n $TRAVIS_BRANCH ]] ; then
        branchInfo=$TRAVIS_BRANCH
    elif [[ -n $TRAVIS_PULL_REQUEST_BRANCH ]] ; then
        branchInfo=$TRAVIS_PULL_REQUEST_BRANCH
    else
        # Current branch is prefixed with an asterisk. Remove it.
        local prefix='* '
        branchInfo=`git branch | grep "$prefix" | sed "s/$prefix//g"`

        # Ensure branch information is useful.
        if [[ -z "$branchInfo" ]] || [[ $branchInfo == *"no branch"* ]] || [[ $branchInfo == *"detached"* ]] ; then
            branchInfo="odf_ci2"
        fi
    fi

    echo "$branchInfo"
}

get_repo()
{
    local repoInfo=

    if [[ -n $CIRCLE_PROJECT_USERNAME ]] && [[ $CIRCLE_PROJECT_REPONAME ]] ; then
        repoInfo="github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
    elif [[ -n $TRAVIS_REPO_SLUG ]] ; then
        repoInfo="github.com/${TRAVIS_REPO_SLUG}"
    else
        if [[ -n $CIRCLE_REPOSITORY_URL ]] ; then
            repoInfo=$CIRCLE_REPOSITORY_URL
        else
            repoInfo=$(git config --get remote.origin.url)
        fi

        # Convert ssh repo url into https
        if echo $repoInfo | grep "@.*:.*/" > /dev/null 2>&1 ; then
            echo $repoInfo | tr @ "\n" | tr : / | tail -1
            return
        fi
    fi

    echo "$repoInfo"
}

BRANCH=$(get_branch)
REPO=$(get_repo)
FOLDER=$(basename $REPO .git)
CONTAINER_NAME=$(echo "$ONEBOX_PARAMS" | tr -d "-" | tr -d " ")

echo "BRANCH=$BRANCH, REPO=$REPO, FOLDER=$FOLDER"
echo "ONEBOX_PARAMS=$ONEBOX_PARAMS"
echo "CONTAINER_NAME=$CONTAINER_NAME"
echo

# keep alive
bash ./tests/keep-alive.sh &

# Connect to container
docker exec -i $CONTAINER_NAME /bin/bash -s <<EOF

# test systemd
if systemctl > /dev/null ; then
    echo "success: has systemd"
else
    echo "FAILURE: no systemd"
    exit 1
fi

# install git
apt update -qq
if apt install git -y -qq ; then
    echo "success: apt install git"
else
    echo "FAILURE: can't apt install git"
    exit 1
fi

# clone repo
mkdir /oxa
pushd /oxa
if git clone --quiet --depth=50 --branch=$BRANCH https://${REPO} ; then
    echo "success: clone repo inside of container"
else
    echo "FAILURE: can't clone repo inside of container"
    exit 1
fi

pushd $FOLDER

# run custom tests
if bash onebox.sh $ONEBOX_PARAMS ; then
    echo "success: onebox deployed"
else
    echo "FAILURE: onebox wasn't deployed"
    exit 1
fi

EOF
