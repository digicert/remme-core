#!/usr/bin/env bash

eval `python3 /scripts/toml-to-env.py`

ADDITIONAL_ARGS=""

echo "Economy enabled: $REMME_ECONOMY_ENABLED"

if [ ! -f /etc/sawtooth/keys/validator.priv ]; then
    echo "validator key pair not found - creating a new one..."
    sawadm keygen
fi

if [ "$REMME_START_MODE" = "genesis" ]; then
    echo "Building the genesis block..."

    if [ -d /var/lib/sawtooth ]; then
        echo "Cleaning up blockchain database..."
        rm /var/lib/sawtooth/*
    fi

    echo "Generating initial settings..."
    sawset genesis -k /etc/sawtooth/keys/validator.priv
    GENESIS_BATCHES="config-genesis.batch"

    if [ "$REMME_CONSENSUS" = "devmode" ]; then
        echo "Devmode consensus is set to use. Writing consensus specific settings..."
        sawset proposal create \
            -k /etc/sawtooth/keys/validator.priv \
            sawtooth.consensus.min_wait_time=5 \
            sawtooth.consensus.max_wait_time=30 \
            -o devmode.batch

        GENESIS_BATCHES="$GENESIS_BATCHES devmode.batch"
    elif [ "$REMME_CONSENSUS" = "remme" ]; then
        echo "REMME consensus is set to use. Writing consensus specific settings..."
        sawset proposal create \
        -k /etc/sawtooth/keys/validator.priv \
            remme.consensus.voters_number=1 \
            remme.consensus.timing=3 \
            remme.consensus.allowed_validators="$(cat /etc/sawtooth/keys/validator.pub)" \
            -o consensus.batch

        GENESIS_BATCHES="$GENESIS_BATCHES consensus.batch"
    fi

    echo "Writing REMME settings..."
    echo "Writing out validator public key: "
    cat /etc/sawtooth/keys/validator.pub
    sawset proposal create \
        -k /etc/sawtooth/keys/validator.priv \
        "remme.settings.pub_key_encryption=$(cat /etc/sawtooth/keys/validator.pub)" \
        "remme.settings.genesis_owners=$(cat /etc/sawtooth/keys/validator.pub)" \
        remme.settings.swap_comission=100 \
        -o settings_config.batch

    GENESIS_BATCHES="$GENESIS_BATCHES settings_config.batch"

    if [ "$REMME_ECONOMY_ENABLED" = "True" ]; then
        echo "Economy model is enabled. Writing the batch to enable it..."
        GENESIS_BATCHES="$GENESIS_BATCHES /genesis/batch/token-proposal.batch"
    fi

    echo "Writing batch injector settings..."
    sawset proposal create \
        -k /etc/sawtooth/keys/validator.priv \
        sawtooth.validator.batch_injectors=block_info \
        "sawtooth.validator.block_validation_rules=NofX:1,block_info;XatY:block_info,0;local:0" \
        -o block_info_config.batch

    GENESIS_BATCHES="$GENESIS_BATCHES block_info_config.batch"

    echo "Generating genesis block..."
    sawadm genesis $GENESIS_BATCHES

    echo "Genesis block generated!"
fi

if [ "$REMME_START_MODE" = "run" ] && [ -s "/config/seeds-list.txt" ]; then
    echo "Gettings the seeds list..."
    SEEDS=$(sed ':a;N;$!ba;s/\n/,/g' /config/seeds-list.txt)
    ADDITIONAL_ARGS="$ADDITIONAL_ARGS --seeds $SEEDS --peers $SEEDS"
fi

echo "Starting the validator..."
sawtooth-validator -vv \
    --endpoint tcp://$REMME_VALIDATOR_IP:$REMME_VALIDATOR_PORT \
    --bind component:tcp://127.0.0.1:4004 \
    --bind consensus:tcp://127.0.0.1:5005 \
    --bind network:tcp://0.0.0.0:8800 \
    $ADDITIONAL_ARGS
