#!/usr/bin/env python3
"""A tiny plain-FTP server for IDEPlus's tests. Localhost only, one test user. Not for real use.

Usage: python3 tools/ftp_test_server.py ROOT_DIR PORT USER PASSWORD
"""
import os
import shutil
import socket
import socketserver
import sys

ROOT, PORT, USER, PASSWORD = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]


class Handler(socketserver.StreamRequestHandler):
	def send(self, line):
		self.wfile.write((line + "\r\n").encode())
		self.wfile.flush()

	def handle(self):
		self.cwd, self.user, self.authed, self.pasv, self.rnfr = "/", None, False, None, None
		self.send("220 IDEPlus test server")
		while True:
			raw = self.rfile.readline()
			if not raw:
				break
			line = raw.decode("utf-8", "replace").rstrip("\r\n")
			cmd, _, arg = line.partition(" ")
			cmd = cmd.upper()
			if not self.authed and cmd not in ("USER", "PASS", "QUIT", "FEAT", "SYST", "OPTS", "AUTH"):
				self.send("530 Not logged in")
				continue
			fn = getattr(self, "do_" + cmd, None)
			if fn is None:
				self.send("502 Not implemented")
				continue
			if fn(arg) == "quit":
				break

	def resolve(self, path):
		virtual = os.path.normpath(os.path.join(self.cwd, path or "."))
		if not virtual.startswith("/"):
			virtual = "/" + virtual
		return virtual, os.path.join(ROOT, virtual.lstrip("/"))

	def data(self):
		conn, _ = self.pasv.accept()
		self.pasv.close()
		self.pasv = None
		return conn

	def open_pasv(self):
		self.pasv = socket.socket()
		self.pasv.bind(("127.0.0.1", 0))
		self.pasv.listen(1)
		return self.pasv.getsockname()[1]

	def do_USER(self, a): self.user = a; self.send("331 Password required")
	def do_PASS(self, a):
		if self.user == USER and a == PASSWORD:
			self.authed = True
			self.send("230 Logged in")
		else:
			self.send("530 Login incorrect")
	def do_AUTH(self, a): self.send("502 No TLS on the test server")
	def do_SYST(self, a): self.send("215 UNIX Type: L8")
	def do_FEAT(self, a): self.send("211-Features"); self.send(" MLSD"); self.send(" SIZE"); self.send(" EPSV"); self.send("211 End")
	def do_OPTS(self, a): self.send("200 OK")
	def do_NOOP(self, a): self.send("200 OK")
	def do_TYPE(self, a): self.send("200 Type set")
	def do_PWD(self, a): self.send('257 "%s"' % self.cwd)
	def do_QUIT(self, a): self.send("221 Bye"); return "quit"

	def do_CWD(self, a):
		v, r = self.resolve(a)
		if os.path.isdir(r):
			self.cwd = v
			self.send("250 OK")
		else:
			self.send("550 No such folder")

	def do_EPSV(self, a): self.send("229 Entering Extended Passive Mode (|||%d|)" % self.open_pasv())
	def do_PASV(self, a):
		p = self.open_pasv()
		self.send("227 Entering Passive Mode (127,0,0,1,%d,%d)" % (p >> 8, p & 255))

	def do_SIZE(self, a):
		_, r = self.resolve(a)
		self.send("213 %d" % os.path.getsize(r) if os.path.isfile(r) else "550 No such file")

	def do_MDTM(self, a): self.send("550 Not supported")

	def do_RETR(self, a):
		_, r = self.resolve(a)
		if not os.path.isfile(r):
			self.send("550 No such file")
			return
		self.send("150 Sending")
		conn = self.data()
		with open(r, "rb") as f:
			conn.sendall(f.read())
		conn.close()
		self.send("226 Done")

	def do_STOR(self, a):
		_, r = self.resolve(a)
		if not os.path.isdir(os.path.dirname(r)):
			self.send("553 No such folder")
			return
		self.send("150 Receiving")
		conn = self.data()
		chunks = []
		while True:
			b = conn.recv(65536)
			if not b:
				break
			chunks.append(b)
		conn.close()
		with open(r, "wb") as f:
			f.write(b"".join(chunks))
		self.send("226 Stored")

	def listing(self, a, line):
		_, r = self.resolve(a)
		if not os.path.isdir(r):
			self.send("550 No such folder")
			return
		self.send("150 Listing")
		conn = self.data()
		out = "".join(line(n, os.path.join(r, n)) + "\r\n" for n in sorted(os.listdir(r)))
		conn.sendall(out.encode())
		conn.close()
		self.send("226 Done")

	def do_MLSD(self, a):
		self.listing(a, lambda n, p: ("type=dir;size=0; " if os.path.isdir(p) else "type=file;size=%d; " % os.path.getsize(p)) + n)

	def do_LIST(self, a):
		self.listing("" if a.startswith("-") else a, lambda n, p: "%s 1 user group %d Jan 01 10:00 %s" % (
			"drwxr-xr-x" if os.path.isdir(p) else "-rw-r--r--", 0 if os.path.isdir(p) else os.path.getsize(p), n))

	def do_NLST(self, a): self.listing(a, lambda n, p: n)

	def do_MKD(self, a):
		v, r = self.resolve(a)
		try:
			os.mkdir(r)
			self.send('257 "%s" created' % v)
		except OSError:
			self.send("550 Can't create folder")

	def do_DELE(self, a):
		_, r = self.resolve(a)
		if os.path.isfile(r):
			os.remove(r)
			self.send("250 Deleted")
		else:
			self.send("550 No such file")

	def do_RMD(self, a):
		_, r = self.resolve(a)
		try:
			os.rmdir(r)
			self.send("250 Removed")
		except OSError:
			self.send("550 Can't remove folder")

	def do_RNFR(self, a):
		_, r = self.resolve(a)
		if os.path.exists(r):
			self.rnfr = r
			self.send("350 Ready")
		else:
			self.send("550 No such file")

	def do_RNTO(self, a):
		_, r = self.resolve(a)
		if self.rnfr:
			shutil.move(self.rnfr, r)
			self.rnfr = None
			self.send("250 Renamed")
		else:
			self.send("503 RNFR first")


class Server(socketserver.ThreadingTCPServer):
	allow_reuse_address = True
	daemon_threads = True


if __name__ == "__main__":
	os.makedirs(ROOT, exist_ok=True)
	with Server(("127.0.0.1", PORT), Handler) as s:
		print("FTP test server on 127.0.0.1:%d serving %s" % (PORT, ROOT), flush=True)
		s.serve_forever()
