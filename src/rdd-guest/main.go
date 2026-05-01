// Package main is the rdd-guest agent that runs inside the Lima/WSL2 VM.
// It listens on a vsock port and forwards connections to the Docker socket,
// enabling the Windows host to reach /var/run/docker.sock via Hyper-V vsock.
package main

import (
	"context"
	"errors"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/mdlayher/vsock"
)

const (
	vsockPort      = 6660
	dockerSockPath = "/var/run/docker.sock"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	l, err := vsock.Listen(vsockPort, nil)
	if err != nil {
		log.Fatalf("vsock listen: %v", err)
	}

	log.Printf("rdd-guest: listening on vsock port %d", vsockPort)

	go func() {
		<-ctx.Done()
		if err := l.Close(); err != nil {
			log.Printf("rdd-guest: close listener: %v", err)
		}
	}()

	for {
		conn, err := l.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("rdd-guest: accept: %v", err)
			if errors.Is(err, syscall.ECONNABORTED) {
				continue
			}
			select {
			case <-time.After(time.Second):
			case <-ctx.Done():
				return
			}
			continue
		}
		go handleConn(ctx, conn)
	}
}

// TODO: once rancher-desktop-daemon is public, replace the inlined halfCloser,
// pipe(), and handleConn() here with a direct import of pkg/socketbridge, which
// contains the implementations (HalfCloser interface, Pipe function).

// halfCloser is a net.Conn that can independently close the write side.
type halfCloser interface {
	net.Conn
	CloseWrite() error
}

// handleConn forwards bytes between the vsock connection and the Docker socket.
// It rejects connections that do not originate from the Windows host (CID 2 /
// vsock.Host): any process in any WSL2 distro shares the same vsock namespace
// and could otherwise gain root Docker API access.
func handleConn(ctx context.Context, vsockConn net.Conn) {
	defer func() {
		if err := vsockConn.Close(); err != nil {
			log.Printf("rdd-guest: close vsock conn: %v", err)
		}
	}()

	addr, ok := vsockConn.RemoteAddr().(*vsock.Addr)
	if !ok || addr.ContextID != vsock.Host {
		log.Printf("rdd-guest: rejected connection from %v", vsockConn.RemoteAddr())
		return
	}

	dockerConn, err := (&net.Dialer{}).DialContext(ctx, "unix", dockerSockPath)
	if err != nil {
		log.Printf("rdd-guest: dial docker: %v", err)
		return
	}
	defer func() {
		if err := dockerConn.Close(); err != nil {
			log.Printf("rdd-guest: close docker conn: %v", err)
		}
	}()

	vsockHC, ok := vsockConn.(halfCloser)
	if !ok {
		log.Printf("rdd-guest: vsock conn from %v does not support CloseWrite", vsockConn.RemoteAddr())
		return
	}
	dockerHC, ok := dockerConn.(halfCloser)
	if !ok {
		log.Printf("rdd-guest: docker conn for %v does not support CloseWrite", vsockConn.RemoteAddr())
		return
	}
	pipe(vsockHC, dockerHC)
}

// pipe bidirectionally proxies between a and b until both directions are done.
func pipe(a, b halfCloser) {
	var wg sync.WaitGroup

	forward := func(dst, src halfCloser) {
		defer wg.Done()
		_, err := io.Copy(dst, src)
		if err != nil && !errors.Is(err, io.EOF) {
			log.Printf("rdd-guest: copy: %v", err)
		}
		_ = dst.CloseWrite()
	}

	wg.Add(2)
	go forward(a, b)
	go forward(b, a)
	wg.Wait()
}
