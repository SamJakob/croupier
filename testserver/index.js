const http = require('http');
const socketClusterServer = require('socketcluster-server');

let httpServer = http.createServer();
let agServer = socketClusterServer.attach(httpServer);

(async () => {
  // Handle new inbound sockets.
  for await (let {socket} of agServer.listener('connection')) {

    console.log(`Socket ${socket.id} connected.`);

    (async () => {
      // Set up a loop to handle remote transmitted events.
      for await (let data of socket.receiver('customRemoteEvent')) {
        console.log("custom...");
        // ...
      }

      for await (let data of socket.receiver('shutdown')) {
        console.log("Shutdown command issued...");

        await new Promise((resolve, reject) => {
          httpServer.close((er) => {
            if (er) return reject();
            resolve();
          });
        });

        process.exit(0);
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

