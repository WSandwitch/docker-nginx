const {before, test} = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');

const nginxHost = process.env.NGINX_HOST || 'nginx';
const consulUrl = process.env.CONSUL_URL || 'http://consul:8500';

function connect(port, payload) {
    return new Promise((resolve, reject) => {
        const socket = net.createConnection({host: nginxHost, port}, () => {
            socket.write(payload);
        });
        const chunks = [];
        const timer = setTimeout(() => {
            socket.destroy();
            reject(new Error(`timeout on port ${port}`));
        }, 5000);

        socket.on('data', (chunk) => chunks.push(chunk));
        socket.on('end', () => {
            clearTimeout(timer);
            resolve(Buffer.concat(chunks).toString());
        });
        socket.on('error', (error) => {
            clearTimeout(timer);
            reject(error);
        });
    });
}

async function waitPort(port, timeoutMs = 60000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            await new Promise((resolve, reject) => {
                const socket = net.createConnection({host: nginxHost, port});
                socket.setTimeout(500);
                socket.on('connect', () => {
                    socket.end();
                    resolve();
                });
                socket.on('timeout', () => {
                    socket.destroy();
                    reject(new Error('timeout'));
                });
                socket.on('error', reject);
            });
            return;
        } catch (_) {
            await new Promise((resolve) => setTimeout(resolve, 500));
        }
    }
    throw new Error(`timeout waiting for port ${port}`);
}

async function putConsulBackend() {
    const response = await fetch(`${consulUrl}/v1/kv/upstreams/test/172.23.0.12:9000`, {
        method: 'PUT',
        body: JSON.stringify({weight: 1, max_fails: 2, fail_timeout: 10}),
    });
    assert.equal(response.status, 200);
}


before(async () => {
    await waitPort(9003);
});

test('stream-upsync dynamic backend', async () => {
    await putConsulBackend();

    const seen = new Set();
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline && seen.size < 2) {
        try {
            seen.add(await connect(9003, 'dynamic'));
        } catch (_) {
            // retry
        }
        await new Promise((resolve) => setTimeout(resolve, 200));
    }

    assert.deepEqual([...seen].sort(), ['one:dynamic', 'two:dynamic']);
});
