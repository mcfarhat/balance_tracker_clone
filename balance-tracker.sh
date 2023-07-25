#!/usr/bin/env bash

set -e

print_help() {
cat <<-END
  Usage: $0 <command> [subcommand] [option(s)]

  Commands:
    build                                 Build the project
    help                                  Show this help screen and exit
    install                               Perform installation steps
    process-blocks                        Process blocks
    run-tests                             Runs tests
    serve                                 Start server
    set-up-database                       Set up the database

  Build subcommands:
    frontend                              Builds the frontend

  Install subcommands:
    jmeter                                Installs Apache Jmeter
    postgrest                             Installs PostgREST
    backend-runtime-dependencies          Installs backend runtime dependencies
    frontend-runtime-dependencies         Installs frontend runtime dependencies
    test-dependencies                     Installs test dependencies

  Serve subcommands:
    frontend                              Start frontend server
    postgrest-backend                     Start PostgREST backend server
    test-results                          Serve test results generated by run-tests command

  Database setup (set-up-database) options:
    --postgres-host=HOSTNAME              PostgreSQL hostname (default: haf_admin)
    --postgres-port=PORT                  PostgreSQL port (default: localhost)
    --postgres-user=USERNAME              PostgreSQL user name (default: 5432)
    --postgres-url=URL                    PostgreSQL URL (if set, overrides three previous options, empty by default)
    --remove-context=true|false           When set to true, remove the balance tracker app context from database before setup (default: false)
    --remove-context                      The same as '--remove-context=true'
    --skip-if-db-exists=true|false        When set to true, skip database setup if database already exists (default: false)
    --skip-if-db-exists                   The same as '--skip-if-db-exists=true'

  Block processing (process-blocks) options:
    --number-of-blocks=INTEGER            Number of blocks to process (default: 10^9), if set to value greater than number of blocks in the database (or 0),
                                            indexer will wait for new blocks
    --postgres-host=HOSTNAME              PostgreSQL hostname (default: haf_admin)
    --postgres-port=PORT                  PostgreSQL port (default: localhost)
    --postgres-user=USERNAME              PostgreSQL user name (default: 5432)
    --postgres-url=URL                    PostgreSQL URL (if set, overrides three previous options, empty by default)
    --log-dir=DIR-PATH                    Directory for block procesing logs (default: unset),
                                            setting this parameter will cause the block processing to run in the background,
                                            logs will be rotated once they reach 5M size

  Test running options:
    --test-report-dir=PATH                Directory where HTML test report will be generated
    --test-result-path=PATH               File where JTL test result will be generated

  Serving options:
    --frontend-port=PORT                  Frontend port (default: 4000)
    --log-dir=PATH                        Log directory for frontend and/or backend logs
    --postgres-host=HOSTNAME              PostgreSQL hostname (default: haf_admin)
    --postgres-port=PORT                  PostgreSQL port (default: localhost)
    --postgres-user=USERNAME              PostgreSQL user name (default: 5432)
    --postgres-url=URL                    PostgreSQL URL (if set, overrides three previous options, empty by default)
    --postgrest-host=HOST                 PostgREST bind address (default: !4)
                                          See https://postgrest.org/en/stable/references/configuration.html#server-host for 
                                          possible values
    --postgrest-port=PORT                 PostgREST bind port (default: 3000)
    --postgrest-admin-server-port=PORT    PostgREST admin port (default: unset, health checks not available)
                                          See https://postgrest.org/en/stable/references/admin.html#health-check for details
    --test-server-port=PORT               Port on which the test report is served
    --test-report-dir=PATH                Directory where HTML test report is located             
      
END
}

build() {
  subcommand=$1
  shift

  case "$subcommand" in
    frontend)
      echo "Building frontend"
      cd gui
      export NODE_ENV=production
      npm install
      npm run build
      npx react-inject-env set
      cd ..
      echo "Finished building frontend"
      ;;
    *)
      echo "Unknown subcommand: $subcommand"
      print_help
      exit 1
  esac
}

install-jmeter() {
  version="5.6.2"
  bin_path="/usr/local/bin/jmeter"
  src_path="/usr/local/src/jmeter-$version"
  echo "Installing Jmeter $version to $bin_path..."

  wget "https://downloads.apache.org/jmeter/binaries/apache-jmeter-${version}.zip" -O jmeter.zip

  unzip "jmeter.zip"
  rm "jmeter.zip"
  sudo mv "apache-jmeter-${version}" "$src_path"

  jmeter="$bin_path-$version"

cat <<-_jmeter | sudo tee "$jmeter"
#!/usr/bin/env bash

cd "$src_path/bin"
./jmeter.sh "\$@"
_jmeter
  
  sudo chmod +x "$jmeter"
  sudo ln -sf "$jmeter" "$bin_path"

  echo "Finished installing Jmeter"
}

install-postgrest() {
  version="v11.1.0"
  path="/usr/local/bin/postgrest"
  echo "Installing PostgREST $version to $path..."

  wget https://github.com/PostgREST/postgrest/releases/download/$version/postgrest-$version-linux-static-x64.tar.xz -O postgrest.tar.xz

  tar -xJf postgrest.tar.xz

  sudo mv postgrest "$path"
  
  rm postgrest.tar.xz
  echo "Finished installing PostgrREST"
}

install-backend-runtime-dependencies() {
  echo "Installing backend runtime dependencies..."
  sudo apt-get update
  sudo apt-get -y install \
    apache2-utils \
    curl \
    postgresql-client \
    wget \
    xz-utils
  echo "Finished installing backend runtime dependencies"
}

install-frontend-runtime-dependencies() {
  echo "Installing frontend runtime dependencies..."
  sudo apt-get update
  sudo apt-get -y install curl
  curl https://get.volta.sh | bash
  export VOLTA_HOME="$HOME/.volta"
  export PATH="$VOLTA_HOME/bin:$PATH"
  cd gui
  npm install
  cd ..
  echo "Finished installing frontend runtime dependencies"
}

install-test-dependencies() {
  echo "Installing test dependencies..."
  sudo apt-get update
  sudo apt-get -y install \
    openjdk-8-jdk-headless \
    python3 \
    unzip
  echo "Finished installing test dependencies"
}

install() {
  subcommand=$1
  shift

  case "$subcommand" in
    jmeter)
      install-jmeter
      ;;
    postgrest)
      install-postgrest
      ;;
    backend-runtime-dependencies)
      install-backend-runtime-dependencies
      ;;
    frontend-runtime-dependencies)
      install-frontend-runtime-dependencies
      ;;
    test-dependencies)
      install-test-dependencies
      ;;
    *)
      echo "Unknown subcommand: $subcommand"
      print_help
      exit 1
  esac
}

process-blocks() {
  echo "Running indexer..."
  echo "Arguments: $*"

  block_number=${BLOCK_NUMBER:-}
  postgres_user=${POSTGRES_USER:-"haf_admin"}
  postgres_host=${POSTGRES_HOST:-"localhost"}
  postgres_port=${POSTGRES_PORT:-5432}
  postgres_url=${POSTGRES_URL:-""}
  log_dir=${LOG_DIR:-}

  while [ $# -gt 0 ]; do
    case "$1" in
      --number-of-blocks=*)
        block_number="${1#*=}"
        ;;
      --postgres-host=*)
        postgres_host="${1#*=}"
        ;;
      --postgres-port=*)
        postgres_port="${1#*=}"
        ;;
      --postgres-user=*)
        postgres_user="${1#*=}"
        ;;
      --postgres-url=*)
        postgres_url="${1#*=}"
        ;;
      --log-dir=*)
        log_dir="${1#*=}"
        ;;
      -*)
          echo "Unknown option: $1"
          print_help
          exit 1
          ;;
      *)
          echo "Unknown argument: $1"
          print_help
          exit 2
          ;;
    esac
    shift
  done

  if [[ -z "$block_number" ]]; then
    block_number=$((10**9))
      
    echo 'Running indexer for existing blocks and expecting new blocks...'
  fi

  postgres_access=${postgres_url:-"postgresql://$postgres_user@$postgres_host:$postgres_port/haf_block_log"}

  if [[ -z "$log_dir" ]]; then
    echo "Running indexer in the foreground"
    psql -a -v "ON_ERROR_STOP=1" "$postgres_access" -c "call btracker_app.main('btracker_app', $block_number);"
    echo "Finished running indexer"
  else
    echo "Running indexer in the background"
    mkdir -p "$log_dir"
    psql -a -v "ON_ERROR_STOP=1" "$postgres_access" -c "call btracker_app.main('btracker_app', $block_number);" 2>&1 | /usr/bin/rotatelogs "$log_dir/process-blocks.%Y-%m-%d-%H_%M_%S.log" 5M &
  fi
}

run-tests() {
  test_scenario_path="$(pwd)/tests/performance/test_scenarios.jmx"
  test_result_path=${TEST_RESULT_PATH:-"$(pwd)/tests/performance/result.jtl"}
  test_report_dir=${TEST_REPORT_DIR:-"$(pwd)/tests/performance/result_report"}

  while [ $# -gt 0 ]; do
    case "$1" in
      --test-report-dir=*)
        test_report_dir="${1#*=}"
        ;;
      --test-result-path=*)
        test_result_path="${1#*=}"
        ;;
      -*)
          echo "Unknown option: $1"
          print_help
          exit 1
          ;;
      *)
          echo "Unknown argument: $1"
          print_help
          exit 2
          ;;
    esac
    shift
  done

  rm -f "$test_result_path"
  mkdir -p "${test_result_path%/*}"
  jmeter -n -t "$test_scenario_path" -l "$test_result_path"

  rm -rf "$test_report_dir"
  mkdir -p "$test_report_dir"
  jmeter -g "$test_result_path" -o "$test_report_dir"
}

start-frontend() {
  echo "Starting frontend..."
  echo "Arguments: $*"

  frontend_port=${FRONTEND_PORT:-}
  log_dir=${LOG_DIR:-}

  while [ $# -gt 0 ]; do
    case "$1" in
      --frontend-port=*)
        frontend_port="${1#*=}"
        ;;
      --log-dir=*)
        log_dir="${1#*=}"
        ;;
      -*)
          echo "Unknown option: $1"
          print_help
          exit 1
          ;;
      *)
          echo "Unknown argument: $1"
          print_help
          exit 2
          ;;
    esac
    shift
  done

  [[ -n "$frontend_port" ]] && export PORT="$frontend_port"

  if [[ -z "$log_dir" ]]; then
    echo "Running frontend in the foreground"
    cd gui
    npm run start
    cd ..
    echo "Finished running frontend"
  else
    echo "Running frontend in the background"
    mkdir -p "$log_dir"
    cd gui
    npm run start 2>&1 | /usr/bin/rotatelogs "$log_dir/frontend.%Y-%m-%d-%H_%M_%S.log" 5M &
    cd ..
  fi
}

start-postgrest() {
  echo "Starting PostgREST..."
  echo "Arguments: $*"

  postgres_user=${POSTGRES_USER:-"haf_admin"}
  postgres_host=${POSTGRES_HOST:-"localhost"}
  postgres_port=${POSTGRES_PORT:-5432}
  postgres_url=${POSTGRES_URL:-""}
  PGRST_SERVER_HOST=${PGRST_SERVER_HOST:-"!4"}
  PGRST_SERVER_PORT=${PGRST_SERVER_PORT:-3000}
  PGRST_ADMIN_SERVER_PORT=${PGRST_ADMIN_SERVER_PORT:-}
  log_dir=${LOG_DIR:-}

  while [ $# -gt 0 ]; do
    case "$1" in
      --postgres-host=*)
        postgres_host="${1#*=}"
        ;;
      --postgres-port=*)
        postgres_port="${1#*=}"
        ;;
      --postgres-user=*)
        postgres_user="${1#*=}"
        ;;
      --postgres-url=*)
        postgres_url="${1#*=}"
        ;;
      --postgrest-host=*)
        PGRST_SERVER_HOST="${1#*=}"
        ;;
      --postgrest-port=*)
        PGRST_SERVER_PORT="${1#*=}"
        ;;
      --postgrest-admin-server-port=*)
        PGRST_ADMIN_SERVER_PORT="${1#*=}"
        ;;
      --log-dir=*)
        log_dir="${1#*=}"
        ;;
      -*)
          echo "Unknown option: $1"
          print_help
          exit 1
          ;;
      *)
          echo "Unknown argument: $1"
          print_help
          exit 2
          ;;
    esac
    shift
  done

  export PGRST_DB_URI=${postgres_url:-"postgresql://$postgres_user@$postgres_host:$postgres_port/haf_block_log"}
  export PGRST_SERVER_HOST
  export PGRST_SERVER_PORT
  export PGRST_ADMIN_SERVER_PORT

  if [[ -z "$log_dir" ]]; then
    echo "Running PostgREST in the foreground"
    postgrest postgrest.conf
    echo "Finished running PostgREST"
  else
    echo "Running PostgREST in the background"
    mkdir -p "$log_dir"
    postgrest postgrest.conf 2>&1 | /usr/bin/rotatelogs "$log_dir/balance-tracker.%Y-%m-%d-%H_%M_%S.log" 5M &
  fi
}

serve-test-results() {
  echo "Starting test result server..."
  echo "Arguments: $*"

  port=${TEST_SERVER_PORT:-8000}
  test_report_dir=${TEST_REPORT_DIR:-"$(pwd)/tests/performance/result_report"}

  while [ $# -gt 0 ]; do
    case "$1" in
      --test-report-dir=*)
        test_report_dir="${1#*=}"
        ;;
      --test-server-port=*)
        port="${1#*=}"
        ;;
      -*)
          echo "Unknown option: $1"
          print_help
          exit 1
          ;;
      *)
          echo "Unknown argument: $1"
          print_help
          exit 2
          ;;
    esac
    shift
  done

  python3 -m http.server --directory "$test_report_dir" "$port"
}

serve() {
  echo "Starting server..."
  echo "Arguments: $*"

  subcommand=$1
  shift

  case "$subcommand" in
    frontend)
      start-frontend "$@"
      ;;
    postgrest-backend)
      start-postgrest "$@"
      ;;
    test-results)
      serve-test-results "$@"
      ;;
    *)
      echo "Unknown subcommand: $subcommand"
      print_help
      exit 1
  esac

  echo "Done"
}

set-up-database() {
  echo "Setting up the database..."
  echo "Arguments: $*"
  ./scripts/setup_db.sh "$@"
  echo "Finished setting up the database"
}

command=$1
shift

case "$command" in
  build)
    build "$@"
    ;;
  install)
    install "$@"
    ;;
  process-blocks)
    process-blocks "$@"
    ;;
  run-tests)
    run-tests "$@"
    ;;
  serve)
    serve "$@"
    ;;
  set-up-database)
    set-up-database "$@"
    ;;
  help | --help | -?)
    print_help
    exit 0
    ;;
  *)
    echo "Unknown command: $command"
    print_help
    exit 1
    ;;
esac