#!/bin/sh
set -eu

if [ -z "$INPUT_REMOTE_DOCKER_HOST" ]; then
    echo "Input remote_docker_host is required!"
    exit 1
fi

# Ignore SSH keys when using Tailscale SSH
if [ -n "$INPUT_TAILSCALE_SSH" ];
then
  echo "Tailscale SSH mode enabled, Manual SSH keys not required"
else
    echo "Normal SSH mode, checking SSH keys"
    if [ -z "$INPUT_SSH_PUBLIC_KEY" ]; then
        echo "Input ssh_public_key is required!"
        exit 1
    fi

    if [ -z "$INPUT_SSH_PRIVATE_KEY" ]; then
        echo "Input ssh_private_key is required!"
        exit 1
    fi
fi

if [ -z "$INPUT_ARGS" ]; then
  echo "Input input_args is required!"
  exit 1
fi

if [ -z "$INPUT_COMPOSE_FILE_PATH" ]; then
  INPUT_COMPOSE_FILE_PATH=docker-compose.yml
fi

if [ -z "$INPUT_SSH_PORT" ]; then
  INPUT_SSH_PORT=22
fi

DOCKER_HOST=ssh://${INPUT_REMOTE_DOCKER_HOST}:${INPUT_SSH_PORT}

SSH_HOST=${INPUT_REMOTE_DOCKER_HOST#*@}

# set context
echo "Create docker context"
docker context create remote --docker "host=ssh://$INPUT_REMOTE_DOCKER_HOST:$INPUT_SSH_PORT"
docker context use remote

if [ -n "$INPUT_UPLOAD_DIRECTORY" ];
then
    echo "upload_directory enabled"
    if [ -z "$INPUT_DOCKER_COMPOSE_DIRECTORY" ]; 
    then
      echo "Input docker_compose_directory is required when upload_directory is enabled!"
      exit 1
    fi
    tar cjvf - -C "$GITHUB_WORKSPACE" "$INPUT_DOCKER_COMPOSE_DIRECTORY" | ssh -o StrictHostKeyChecking=no "$INPUT_REMOTE_DOCKER_HOST" -p "$INPUT_SSH_PORT" 'tar -xjvf -'
    echo "Upload finished"
    if [ -n "$INPUT_POST_UPLOAD_COMMAND" ];
      then
      echo "Upload post command specified, runnig. $INPUT_POST_UPLOAD_COMMAND"
      ssh -o StrictHostKeyChecking=no "$INPUT_REMOTE_DOCKER_HOST" -p "$INPUT_SSH_PORT" "eval $INPUT_POST_UPLOAD_COMMAND"
    fi
fi

if  [ -n "$INPUT_DOCKER_LOGIN_PASSWORD" ] || [ -n "$INPUT_DOCKER_LOGIN_USER" ] || [ -n "$INPUT_DOCKER_LOGIN_REGISTRY" ]; then
  echo "Connecting to $INPUT_REMOTE_DOCKER_HOST... Command: docker login"
  docker login -u "$INPUT_DOCKER_LOGIN_USER" -p "$INPUT_DOCKER_LOGIN_PASSWORD" "$INPUT_DOCKER_LOGIN_REGISTRY"
fi

if [ -n "$INPUT_DOCKER_SWARM" ];
then
  echo "docker swarm mode enabled, using docker stack command"
  echo "Command: docker ${INPUT_ARGS} stack deploy --compose-file ${INPUT_COMPOSE_FILE_PATH}"
  docker ${INPUT_ARGS} stack deploy --compose-file ${INPUT_COMPOSE_FILE_PATH}
else
  echo "Command: docker compose -f ${INPUT_COMPOSE_FILE_PATH} pull"
  docker compose -f ${INPUT_COMPOSE_FILE_PATH} pull

  echo "Command: docker compose -f ${INPUT_COMPOSE_FILE_PATH} ${INPUT_ARGS}"
  docker compose -f ${INPUT_COMPOSE_FILE_PATH} ${INPUT_ARGS}
fi

if [ -n "$INPUT_POST_UP_COMMAND" ];
then
  echo "Healthcheck $INPUT_POST_UP_COMMAND"
  ssh -o StrictHostKeyChecking=no "$INPUT_REMOTE_DOCKER_HOST" -p "$INPUT_SSH_PORT" "eval $INPUT_POST_UP_COMMAND"
fi