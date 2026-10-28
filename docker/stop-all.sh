#!/bin/bash
set -e
sh start-middleware.sh stop
sh start-execute.sh stop
sh start-console.sh stop