#!/bin/bash
set -e
sh start-middleware.sh start
sh start-execute.sh start
sh start-console.sh start