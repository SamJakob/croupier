#!/bin/bash
export CLOSE_ON_TEST_FINISH=true
yarn --cwd ./testserver/ start & dart pub run test