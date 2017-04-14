#!/bin/bash

# vars
ROOT_DIR="/home/$(whoami)/hypothesis/"



announce_part () { #just printing stuff
  message=$@
  size=${#message}
  cols=$(tput cols)
  seplen=$(printf %.0f $(bc -l <<< "($cols - $size - 2)/2"))
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
    if [ "$H_RANGE" == "local" ]; then
    export CLIENT_URL=http://localhost:3001/hypothesis
  elif [ "$H_RANGE" == "lan" ]; then
    export CLIENT_URL=http://192.168.1.253:3001/hypothesis
  elif [ "$H_RANGE" == "global" ]; then
    export CLIENT_URL=http://134.214.253.133:3001/hypothesis
  fi
  announce_part "Launching hypothesis server"
  cd $ROOT_DIR/h
  source .venv/bin/activate
  screen -S hypothesis_server -d -m make dev
}

start_hypothesis_client () {
  if [ "$H_RANGE" == "local" ]; then
    export H_SERVICE_URL=http://localhost:5000
  elif [ "$H_RANGE" == "lan" ]; then
    export H_SERVICE_URL=http://192.168.1.253:5000
  elif [ "$H_RANGE" == "global" ]; then
    export H_SERVICE_URL=http://134.214.253.133:5000
  fi
  announce_part "Launching hypothesis client"
  cd $ROOT_DIR/client/
  screen -S hypothesis_client -d -m gulp watch
}

mkdir -p $ROOT_DIR
cd $ROOT_DIR

if [ "$H_RANGE" == "" ]; then
  echo "Environment variable H_RANGE (local|lan|global) not set. Defaulting to lan."
  export H_RANGE=lan
fi


if [ "$1" == "" ];then

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

elif [ "$1" == "part2" ]; then
  cd $ROOT_DIR/h

  announce_part "Creating virtual environment"
  virtualenv .venv
  source .venv/bin/activate

  announce_part "Starting rabbit, postgres & elastic servers"

  echo "currently in $(pwd)"
  echo "Starting server for the first time. This may take a while..."
  #screen -S rabbit_postgres_elastic -d -m docker-compose up
  docker-compose up -d
  #docker-compose up
  while true;do
    nc -z localhost 5432 && \
      echo "port open" && \
      docker-compose exec postgres psql -U postgres -c "DROP DATABASE IF EXISTS htest;" 2>/dev/null && \
      break
    sleep 1
  done
  echo "Server launched !"
  sleep 1
  docker-compose exec postgres psql -U postgres -c "CREATE DATABASE htest;"

  announce_part "Checking if everything works"
  echo "This will take a while too. Buckle up !"
  make test || { echo "So apparently some of the tests failed. This is not supposed to happen, so I'll just let you solve the problem and call me back when you're finished"; exit -1; }

  announce_part "Opening server to the outside world"
  sed 's/host: localhost/host: 0.0.0.0/' < conf/development-app.ini > /tmp/blob3000
  rm conf/development-app.ini
  mv /tmp/blob3000 conf/development-app.ini

  exec $0 part3

elif [ "$1" == "part3" ]; then
  announce_part "Installing hypothesis client"
  cd $ROOT_DIR
  git clone 'https://github.com/hypothesis/client.git'
  cd client
  sudo npm install -g gulp-cli
  make



  echo "everything installed."

  $0 launch

elif [ "$1" == "launch" ]; then
  start_hypothesis_server
  start_hypothesis_client

  announce_part "Deployment over"
else
  echo "If this prints, I can't bash."
fi

