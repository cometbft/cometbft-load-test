package main

import (
	"github.com/cometbft/cometbft-load-test/pkg/loadtest"
)

const appLongDesc = `Load testing application for CometBFT with optional coordinator/worker mode.
Generates large quantities of arbitrary transactions and submits those
transactions to one or more CometBFT endpoints. By default, it assumes that you
are running the kvstore ABCI application on your CometBFT network.

To run the application in STANDALONE mode:
    cometbft-load-test -c 1 -T 10 -r 1000 -s 250 \
        --broadcast-tx-method async \
        --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket

To run the application in COORDINATOR mode:
    cometbft-load-test \
        coordinator \
        --expect-workers 2 \
        --bind localhost:26670 \
        --shutdown-wait 60 \
        -c 1 -T 10 -r 1000 -s 250 \
        --broadcast-tx-method async \
        --endpoints ws://cmt-endpoint1.somewhere.com:26657/websocket,ws://cmt-endpoint2.somewhere.com:26657/websocket

To run the application in WORKER mode:
    cometbft-load-test worker --coordinator localhost:26680

NOTES:
* COORDINATOR mode exposes a "/metrics" endpoint in Prometheus plain text
* format
  which shows total number of transactions and the status for the coordinator
  and all connected workers.
* The "--shutdown-wait" flag in COORDINATOR mode is specifically to allow your
  monitoring system some time to obtain the final Prometheus metrics from the
  metrics endpoint.
* In WORKER mode, all load testing-related flags are ignored. The worker always
  takes instructions from the coordinator node it's connected to.
`

func main() {
	loadtest.Run(&loadtest.CLIConfig{
		AppName:              "cometbft-load-test",
		AppShortDesc:         "Load testing application for CometBFT kvstore",
		AppLongDesc:          appLongDesc,
		DefaultClientFactory: "kvstore",
	})
}
