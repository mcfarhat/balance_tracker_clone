#!/bin/bash

set -e
set -o pipefail

clean_data() {
    psql -a -v "ON_ERROR_STOP=1" "$@" -d haf_block_log -c '\timing' -c "do \$\$ BEGIN if hive.app_context_exists('btracker_app') THEN perform hive.app_remove_context('btracker_app'); end if; END \$\$"
}

create_db() {
    psql -a -v "ON_ERROR_STOP=1" "$@" -d haf_block_log -f $PWD/db/btracker_app.sql
}

run_indexer() {
    psql -a -v "ON_ERROR_STOP=1" "${@:2}" -d haf_block_log -c '\timing' -c "call btracker_app.main('btracker_app', $1);"
}

create_api() {
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -f $PWD/api/btracker_api.sql
}

create_user() {
    psql -a -v "ON_ERROR_STOP=1" -d haf_block_log -c '\timing' -c "call btracker_app.create_api_user();"
}

start_webserver() {
    postgrest webserver.conf
}

install_postgrest() {
    wget https://github.com/PostgREST/postgrest/releases/download/v8.0.0/postgrest-v8.0.0-linux-x64-static.tar.xz

    POSTGREST=$(find . -name 'postgrest*')
    tar xJf $POSTGREST
    sudo mv 'postgrest' '/usr/local/bin/postgrest'
    rm $POSTGREST
}

restart_all() {
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]]; then
        echo 'ERROR: Second argument must be block number'
        exit 1
    fi

    clean_data ${@:2}
    create_db ${@:2}
    run_indexer $@
    create_api
    create_user
}

if [ "$1" = "re-all" ]; then
    restart_all ${@:2}
    echo 'SUCCESS: DB and API recreated'
elif [ "$1" = "re-all-start" ]; then
    restart_all ${@:2}
    echo 'SUCCESS: DB and API recreated'
    start_webserver
elif [ "$1" = "re-api" ]; then
    create_api
    echo 'SUCCESS: API recreated'
elif [ "$1" = "re-api-start" ]; then
    create_api
    echo 'SUCCESS: API recreated'
    start_webserver
elif [ "$1" = "install" ]; then
    install_postgrest
elif [ "$1" = "start" ]; then
    start_webserver
fi