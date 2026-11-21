const net = require('node:net');

const prefix = process.env.PREFIX || '';

const server = net.createServer((socket) => {
    socket.on('data', (chunk) => {
        socket.write(prefix + chunk.toString());
    });
});

server.listen(9000, '0.0.0.0');
