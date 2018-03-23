#!/bin/bash

# vars
ROOT_DIR="$(echo ~)/hypothesis/"

set -e # if a command fails, stop script
set -u # if an rvalue is undefined then fail
set -o pipefail # report fail through pipes

setup_env () {
  export h="http://localhost"

  #SECRET_KEY={{ lookup('password', '/dev/null length=64') }}
  export CLIENT_ID=hyperthesis_client
  #CLIENT_SECRET={{ lookup('password', '/dev/null length=36') }}

  #CLIENT_URL=https://{{ h_server_name }}/hypothesis
  export CLIENT_URL=$h:3001/hypothesis

  #H_SERVICE_URL=https://{{ h_server_name }}
  export H_SERVICE_URL=$h:5000

  #SIDEBAR_APP_URL=https://{{ h_server_name }}/app.html
  export SIDEBAR_APP_URL=$h:5000/app.html

  #H_EMBED_URL=https://{{ h_server_name }}/embed.js
  export H_EMBED_URL=$h:5000/embed.js
  export APP_URL=$h:5000
  #BOUNCER_URL=https://{{ bouncer_server_name }}
  #BROKER_URL=amqp://guest:guest@rabbit:5672//
  export AUTHORITY=localhost
  export CLIENT_OAUTH_ID="f9e88ccc-276c-11e8-bbe3-87c43cb5b86b"

  export VIA_BASE_URL=$h:9080
  #export ELASTICSEARCH_HOST=elasticsearch
  #export ELASTICSEARCH_PORT=9200
  export HYPOTHESIS_URL=$h:5000

  #export STATSD_HOST=graphite
  #export STATSD_PORT=8125

  #export GRAPHITE_HOST=graphite

}

announce_part () { #just printing stuff
  message=$@
  size=${#message}
  cols=$(tput cols)
  seplen=$(LC_NUMERIC="en_US.UTF-8" printf %.0f $(bc -l <<< "($cols - $size - 2)/2"))
  echo ""
  for ((i=0; i<$seplen; i++));do
    echo -n "#"
  done
  #echo -$size $cols $seplen
  echo -n " "$message" "
  for ((i=$seplen + ${#message} + 2; i<$cols; i++));do
    echo -n "#"
  done
  echo ""
  echo ""
}

start_hypothesis_server () {
  announce_part "Launching hypothesis server"
  pushd $ROOT_DIR/h
  set +u; source .venv/bin/activate; set -u
  screen -S h_server -d -m make dev
  popd
}

start_hypothesis_client () {
  announce_part "Launching hypothesis client"
  pushd $ROOT_DIR/client/
  screen -S h_client -d -m gulp watch
  popd
}

start_hypothesis_via () {
  announce_part "Launching hypothesis via"
  pushd $ROOT_DIR/via
  set +u; source .venv/bin/activate; set -u
  screen -S h_via -d -m make serve
  popd
}

start_requirements () {

  pushd $ROOT_DIR/h

  docker-compose up -d
  #docker-compose up
  echo "waiting for database server..."
  while true;do
    nc -z localhost 5432 && \
      echo "port open" && \
      docker-compose exec postgres psql -U postgres -c "DROP DATABASE IF EXISTS htest;" 2>/dev/null && \
      break
    sleep 1
  done

  popd
}

setup_env
mkdir -p $ROOT_DIR
pushd $ROOT_DIR


#echo "Environment variable H_RANGE (local|lan|global) not set. Defaulting to local." &&
export H_RANGE=${H_RANGE:=local}
arg=${1:-} # default argument to empty string


if [ "$arg" == "" ];then
  #announce_part "installing script requirements"
  sudo echo "User already sudoer" && exec $0 part2 || announce_part "making current user sudoer"
  export sudoUser=$(whoami)
  su -c 'apt update -qq; apt -y upgrade -qq; apt install sudo; usermod -aG sudo $sudoUser'
  exec sudo su -c "$0 part2" -l $(whoami) #refresh groups and start part 1

elif [ "$arg" == "part1" ];then
  announce_part "Upgrading packages"
  sudo apt update -qq
  sudo apt -y upgrade -qq

  announce_part "Installing dependencies"
  # Wheezy:
  sudo apt -y -q install \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    screen \
    build-essential \
    libssl-dev \
    git \
    libevent-dev \
    libffi-dev \
    libfontconfig \
    libpq-dev \
    python-dev \
    python-pip \
    python-virtualenv
  sudo pip install -U pip virtualenv

  announce_part "Installing Docker"
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository \
          "deb [arch=amd64] https://download.docker.com/linux/debian \
          $(lsb_release -cs) \
          stable"
  sudo apt update -qq
  sudo apt -y install -qq docker-ce
  sudo systemctl enable docker
  sudo systemctl start docker

  announce_part "Installing docker-compose"
  sudo curl -L "https://github.com/docker/compose/releases/download/1.11.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod a+x /usr/local/bin/docker-compose

  announce_part "Installing yarn"
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
  sudo apt update -qq
  sudo apt -y install -qq yarn

  announce_part "Installing nodejs"
  #curl -sL https://deb.nodesource.com/setup_0.12 | sudo bash -
  curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash -
  sudo apt install -qq -y nodejs
  sudo npm install -g npm

  announce_part "Installing nodejs components"
  sudo npm install -g gulp-cli

  announce_part "Cloning Hypothesis"
  git clone https://github.com/hypothesis/h

  announce_part "Setting groups"
  sudo usermod -aG docker $(whoami)
  echo "$(whoami) is now in the docker group. Refreshing rights..."
  exec sudo su -c "$0 part2" -l $(whoami) #refresh groups and start second part

elif [ "$arg" == "part2" ]; then
  cd $ROOT_DIR/h

  announce_part "Creating virtual environment"
  virtualenv .venv

  set +u
  source .venv/bin/activate
  set -u

  announce_part "Starting rabbit, postgres & elastic servers"

  echo "currently in $(pwd)"
  echo "Starting server for the first time. This may take a while..."
  
  start_requirements

  echo "Server launched !"
  sleep 1
  docker-compose exec postgres psql -U postgres -c "CREATE DATABASE htest;"

  announce_part "Checking if h works"
  echo "This will take a while too. Buckle up !"
  make test || { echo "So apparently some of the tests failed. This is not supposed to happen, so I'll just let you solve the problem and call me back when you're finished"; exit -1; }

  announce_part "Opening server to the outside world"
  sed 's/host: localhost/host: 0.0.0.0/' < conf/development-app.ini > /tmp/blob3000
  rm conf/development-app.ini
  mv /tmp/blob3000 conf/development-app.ini
  bin/hypothesis --dev authclient add --name=hyperthesis_client --authority=localhost --type=public

  popd
  exec $0 part3

elif [ "$arg" == "part3" ]; then
  announce_part "Installing hypothesis client"
  cd $ROOT_DIR
  git clone 'https://github.com/gus3000/client.git'
  pushd client
  make
  popd
  
  announce_part "Installing hypothesis via"
  git clone "https://github.com/hypothesis/via"
  pushd via
  virtualenv .venv
  set +u; source .venv/bin/activate; set -u
  make deps
  popd

  echo "everything installed."
  popd
  $0 launch

elif [ "$arg" == "launch" ]; then
  start_requirements
  start_hypothesis_server
  start_hypothesis_client
  start_hypothesis_via

  announce_part "Deployment over"
else
  echo "If this prints, I can't bash."
fi

