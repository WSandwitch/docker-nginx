const http = require('node:http');

let cacheRequests = 0;

const server = http.createServer((req, res) => {
    if (req.url === '/body') {
        res.writeHead(200, {'Content-Type': 'text/plain'});
        res.end('foo body '.repeat(1024));
        return;
    }

    if (req.url === '/subs') {
        res.writeHead(200, {'Content-Type': 'text/plain'});
        res.end('foo body');
        return;
    }

    if (req.url === '/cache') {
        cacheRequests += 1;
        res.writeHead(200, {'Content-Type': 'text/plain'});
        res.end(`cache body ${cacheRequests}`);
        return;
    }

    if (req.url === '/count') {
        res.writeHead(200, {'Content-Type': 'text/plain'});
        res.end(String(cacheRequests));
        return;
    }

    res.writeHead(404, {'Content-Type': 'text/plain'});
    res.end('not found');
});

server.listen(3000, '0.0.0.0');
