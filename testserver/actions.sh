#!/bin/bash
export CLOSE_ON_TEST_FINISH=true
dart pub get
yarn --cwd ./testserver/ start & dart pub run test