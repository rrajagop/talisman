#!/bin/bash

GIT_REPO_DOT_GIT=$1
IGNORE_PATTERN=$2

echo $IGNORE_PATTERN >> ${GIT_REPO_DOT_GIT}../.talismanignore
