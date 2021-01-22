const http = require('http');
const socketClusterServer = require('socketcluster-server');

let httpServer = http.createServer();
let agServer = socketClusterServer.attach(httpServer);

(async () => {
  // Handle new inbound sockets.
  for await (let {socket} of agServer.listener('connection')) {

    console.log(`Socket ${socket.id} connected.`);

    (async () => {
      for await (let data of socket.receiver('shutdown')) {
        console.log("Shutdown command issued...");

        await new Promise((resolve, reject) => {
          httpServer.close((er) => {
            if (er) return reject();
            resolve();
          });
        });

        console.log("Restarting...");
        await httpServer.listen(3000);
        console.log("Server listening on localhost:3000");
      }
    })();

    (async () => {
      for await (let data of socket.receiver('testFinish')) {
        console.log("Tests done!");

        await new Promise(resolve => setTimeout(resolve, 200));

        if (process.env.CLOSE_ON_TEST_FINISH) {
          console.log("Closing server...");
          await new Promise((resolve, reject) => {
            httpServer.close((er) => {
              if (er) return reject();
              resolve();
            });
          });

          console.log("Exiting...");
          process.exit(0);
        }
      }
    })();

    (async () => {
      // Set up a loop to handle remote transmitted events.
      for await (let data of socket.receiver('triggerTestRecv')) {
        socket.transmit('testRecv', '4aa78d81f5ff8f60de71c42c86a80b36');
      }
    })();

    (async () => {
      // Set up a loop to handle remote transmitted events.
      for await (let data of socket.receiver('triggerTestInvk')) {
        let response = await socket.invoke('testInvk');
        console.log(response);
        socket.transmit('testInvkResult', response);
      }
    })();

    (async () => {
      // Set up a loop to handle and respond to RPCs for a procedure.
      for await (let req of socket.procedure('customProc')) {
        if (req.data.bad) {
          let error = new Error('Server failed to execute the procedure');
          error.name = 'BadCustomError';
          req.error(error);
        } else {
          req.end('Success');
        }
      }
    })();

    (async () => {
      // Set up a loop to handle remote transmitted events.
      for await (let data of socket.listener('raw')) {
        console.log(data);
      }
    })();

  }
})();

(async () => {
  await httpServer.listen(3000);
  console.log("Server listening on localhost:3000");
})();

