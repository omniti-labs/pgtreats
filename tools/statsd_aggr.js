/*
var cli = require('cli');
cli.parse({
	'thresh' : ['', 'The mtu threshold', 'integer', 1400],
	'timeout': ['', 'The interval to drain_buffer', 'integer', 1000],
	'rhost': ['', 'The remote host', 'string', ''],
	'rport': ['', 'The remote port', 'integer', 8125],
	'lhost': ['', 'The local host', 'string', '127.0.0.1'],
	'rport': ['', 'The local port', 'string', 8125],
});
var thresh = cli.options.thresh;
var timeout = cli.options.timeout;
var rhost = cli.options.rhost;
var rport = cli.options.rport;
var lhost = cli.options.lhost;
var lport = cli.options.lport;
*/

var thresh = 1432; // 1500 - 68
//var thresh = 8932; // 9000 - 68
var timeout = 1000;
var rhost = '';
var rport = 8125;
var lhost = '127.0.0.1';
var lport = 8125;

var dgram = require('dgram');
var buf = new Buffer(thresh);
var length = 0;
var timeoutId;
var client = dgram.createSocket('udp4');

function drain_buffer(event)
{
    if (event != 'time')
    {
        clearTimeout(timeoutId);
    }

    if (length > 0)
    {
        client.send(buf, 0, length, rport, rhost);
        length = 0;
    }

    timeoutId = setTimeout(drain_buffer, timeout, 'time');
}

function handle_packet(msg, rinfo)
{
    if (msg.length >= thresh)
    {
     	client.send(msg, 0, msg.length, rport, rhost);
        return;
    }

    if (length > 0)
    {
     	if (msg.length + length + 1 <= thresh)
        {
            buf.write('\n', length++);
        }
	else
	{
            if (msg.length < length)
            {
             	drain_buffer('full');
            }
            else
            {
             	client.send(msg, 0, msg.length, rport, rhost);
                return;
            }
	}
    }

    msg.copy(buf, length);
    length += msg.length;
}

function handle_exit()
{
    server.close();
    drain_buffer('exit');
}

var server = dgram.createSocket('udp4', handle_packet);
timeoutId = setTimeout(drain_buffer, timeout, 'time');
server.bind(lport, lhost);
process.on('exit', handle_exit);
process.on('SIGINT', process.exit);
process.on('SIGTERM', process.exit);
