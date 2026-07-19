package deploy

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"sync"
)

type Deployer struct {
	ProjectRoot    string
	DeviceID       string
	BuildMode      string
	EnvFile        string
	AppEnv         string
	VMServicePort  int
	UseFVM         bool

	mu              sync.Mutex
	cmd             *exec.Cmd
	stdin           io.WriteCloser
	running         bool
	err             string
	output          []string
	deployGeneration int
	outputRevision   int
	listeners       []chan struct{}
}

func (d *Deployer) CanDeploy() bool {
	return d.ProjectRoot != "" && d.DeviceID != ""
}

func (d *Deployer) IsRunning() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.running
}

func (d *Deployer) HasActiveProcess() bool {
	return d.IsRunning()
}

func (d *Deployer) Error() string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.err
}

func (d *Deployer) DeployGeneration() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.deployGeneration
}

func (d *Deployer) OutputRevision() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.outputRevision
}

func (d *Deployer) RecentOutput() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]string, len(d.output))
	copy(out, d.output)
	return out
}

func (d *Deployer) Notify() <-chan struct{} {
	d.mu.Lock()
	defer d.mu.Unlock()
	ch := make(chan struct{}, 1)
	d.listeners = append(d.listeners, ch)
	return ch
}

func (d *Deployer) notify() {
	for _, ch := range d.listeners {
		select {
		case ch <- struct{}{}:
		default:
		}
	}
}

func (d *Deployer) appendLine(line string) {
	d.mu.Lock()
	d.output = append(d.output, line)
	if len(d.output) > 4000 {
		d.output = d.output[len(d.output)-4000:]
	}
	d.outputRevision++
	d.mu.Unlock()
	d.notify()
}

func (d *Deployer) Stop() {
	d.mu.Lock()
	cmd := d.cmd
	d.cmd = nil
	d.running = false
	d.mu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}
}

func (d *Deployer) Reinstall() bool {
	if !d.CanDeploy() {
		d.mu.Lock()
		d.err = "Missing project root or device id for reinstall"
		d.mu.Unlock()
		return false
	}
	d.mu.Lock()
	if d.running {
		d.mu.Unlock()
		return false
	}
	d.mu.Unlock()

	d.Stop()

	d.mu.Lock()
	d.err = ""
	d.output = nil
	d.deployGeneration++
	d.mu.Unlock()

	args := []string{"run", "-d", d.DeviceID}
	switch d.BuildMode {
	case "profile":
		args = append(args, "--profile",
			fmt.Sprintf("--host-vmservice-port=%d", d.VMServicePort),
			"--disable-service-auth-codes")
	case "release":
		args = append(args, "--release")
	default:
		args = append(args, "--debug",
			fmt.Sprintf("--host-vmservice-port=%d", d.VMServicePort),
			"--disable-service-auth-codes")
	}
	if d.EnvFile != "" {
		args = append(args, "--dart-define-from-file="+d.EnvFile)
		if d.AppEnv != "" {
			args = append(args, "--dart-define=APP_ENV="+d.AppEnv)
		}
	}

	exe := "flutter"
	cmdArgs := args
	if d.UseFVM {
		exe = "fvm"
		cmdArgs = append([]string{"flutter"}, args...)
	}

	cmd := exec.Command(exe, cmdArgs...)
	cmd.Dir = d.ProjectRoot
	stdin, err := cmd.StdinPipe()
	if err != nil {
		d.mu.Lock()
		d.err = "Failed to start flutter reinstall: " + err.Error()
		d.mu.Unlock()
		return false
	}
	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		d.mu.Lock()
		d.err = "Failed to start flutter reinstall: " + err.Error()
		d.mu.Unlock()
		return false
	}

	d.mu.Lock()
	d.cmd = cmd
	d.stdin = stdin
	d.running = true
	d.mu.Unlock()

	d.appendLine("> " + exe + " " + joinArgs(cmdArgs))
	go d.readLines(stdout, "")
	go d.readLines(stderr, "[stderr] ")
	go func() {
		err := cmd.Wait()
		d.mu.Lock()
		d.running = false
		d.cmd = nil
		d.stdin = nil
		if err != nil {
			d.err = fmt.Sprintf("Flutter reinstall exited: %v", err)
			d.mu.Unlock()
			d.appendLine(d.Error())
			return
		}
		d.mu.Unlock()
		d.appendLine("Flutter reinstall finished.")
	}()
	return true
}

func (d *Deployer) readLines(r io.Reader, prefix string) {
	sc := bufio.NewScanner(r)
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 1024*1024)
	for sc.Scan() {
		d.appendLine(prefix + sc.Text())
	}
}

func (d *Deployer) sendKey(key string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.stdin == nil || !d.running {
		return false
	}
	if _, err := io.WriteString(d.stdin, key+"\n"); err != nil {
		d.err = err.Error()
		return false
	}
	d.output = append(d.output, "> "+key)
	d.outputRevision++
	d.notify()
	return true
}

func (d *Deployer) HotReload() bool  { return d.sendKey("r") }
func (d *Deployer) HotRestart() bool { return d.sendKey("R") }
func (d *Deployer) Quit() bool       { return d.sendKey("q") }

func joinArgs(args []string) string {
	out := ""
	for i, a := range args {
		if i > 0 {
			out += " "
		}
		out += a
	}
	return out
}

func DetectFVM() bool {
	_, err := exec.LookPath("fvm")
	return err == nil
}

func HasFlutter() bool {
	if DetectFVM() {
		return true
	}
	_, err := exec.LookPath("flutter")
	return err == nil
}

func Which(bin string) bool {
	_, err := exec.LookPath(bin)
	return err == nil
}