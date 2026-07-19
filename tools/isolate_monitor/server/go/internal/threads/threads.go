package threads

import (
	"os/exec"
	"regexp"
	"strings"
)

type Info struct {
	TID   string `json:"tid"`
	Name  string `json:"name"`
	PID   string `json:"pid,omitempty"`
	State string `json:"state,omitempty"`
}

func Hints() []string {
	return []string{
		"adb: Native threads listed here when the app process is running",
		"Android Studio: Profiler → CPU / Threads",
		"Instruments (iOS): Time Profiler / Threads",
	}
}

func Fetch(deviceSerial, packageName string) map[string]any {
	base := map[string]any{
		"threads": []Info{},
		"hints":   Hints(),
	}
	if strings.TrimSpace(deviceSerial) == "" {
		base["ok"] = false
		base["error"] = "No device selected"
		return base
	}
	if strings.TrimSpace(packageName) == "" {
		base["ok"] = false
		base["error"] = "No Android package id"
		return base
	}
	if _, err := exec.LookPath("adb"); err != nil {
		base["ok"] = false
		base["error"] = "adb not found on PATH"
		return base
	}

	pid := resolvePID(deviceSerial, packageName)
	if pid == "" {
		base["ok"] = false
		base["error"] = "App process not running for " + packageName
		base["package"] = packageName
		base["device"] = deviceSerial
		return base
	}

	list := listThreads(deviceSerial, pid)
	return map[string]any{
		"ok":          true,
		"package":     packageName,
		"device":      deviceSerial,
		"pid":         pid,
		"threadCount": len(list),
		"threads":     list,
		"source":      "adb",
		"hints":       Hints(),
		"note":        "Dart isolates are unavailable in --release. These are native OS threads via adb.",
	}
}

func resolvePID(serial, packageName string) string {
	out, err := exec.Command("adb", "-s", serial, "shell", "pidof", "-s", packageName).Output()
	if err == nil {
		pid := strings.Fields(strings.TrimSpace(string(out)))
		if len(pid) > 0 && regexp.MustCompile(`^\d+$`).MatchString(pid[0]) {
			return pid[0]
		}
	}
	ps, err := exec.Command("adb", "-s", serial, "shell", "ps", "-A").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(ps), "\n") {
		if !strings.Contains(line, packageName) {
			continue
		}
		parts := strings.Fields(strings.TrimSpace(line))
		if len(parts) >= 2 && regexp.MustCompile(`^\d+$`).MatchString(parts[1]) {
			return parts[1]
		}
	}
	return ""
}

func listThreads(serial, pid string) []Info {
	out, err := exec.Command("adb", "-s", serial, "shell", "ps", "-T", "-p", pid).Output()
	if err == nil {
		if parsed := parsePsT(string(out), pid); len(parsed) > 0 {
			return parsed
		}
	}
	script := "for t in /proc/" + pid + "/task/*; do tid=${t##*/}; name=$(cat $t/comm 2>/dev/null); echo \"$tid $name\"; done"
	taskOut, err := exec.Command("adb", "-s", serial, "shell", "sh", "-c", script).Output()
	if err != nil {
		return nil
	}
	var threads []Info
	digit := regexp.MustCompile(`^\d+$`)
	for _, line := range strings.Split(string(taskOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) == 0 || !digit.MatchString(parts[0]) {
			continue
		}
		name := parts[0]
		if len(parts) > 1 {
			name = strings.Join(parts[1:], " ")
		}
		threads = append(threads, Info{TID: parts[0], Name: name, PID: pid})
	}
	return threads
}

func parsePsT(stdout, pid string) []Info {
	lines := strings.Split(stdout, "\n")
	if len(lines) == 0 {
		return nil
	}
	header := strings.ToUpper(strings.TrimSpace(lines[0]))
	cols := strings.Fields(header)
	tidIdx := indexOf(cols, "TID")
	nameIdx := indexOfAny(cols, []string{"NAME", "CMD", "ARGS"})
	pidIdx := indexOf(cols, "PID")
	digit := regexp.MustCompile(`^\d+$`)
	var threads []Info
	for _, line := range lines[1:] {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		tid := parts[0]
		if tidIdx >= 0 && tidIdx < len(parts) {
			tid = parts[tidIdx]
		} else if len(parts) > 1 {
			tid = parts[1]
		}
		if !digit.MatchString(tid) {
			continue
		}
		name := parts[len(parts)-1]
		if nameIdx >= 0 && nameIdx < len(parts) {
			name = strings.Join(parts[nameIdx:], " ")
		}
		rowPid := pid
		if pidIdx >= 0 && pidIdx < len(parts) {
			rowPid = parts[pidIdx]
		}
		threads = append(threads, Info{TID: tid, Name: name, PID: rowPid})
	}
	return threads
}

func indexOf(cols []string, name string) int {
	for i, c := range cols {
		if c == name {
			return i
		}
	}
	return -1
}

func indexOfAny(cols []string, names []string) int {
	for _, n := range names {
		if i := indexOf(cols, n); i >= 0 {
			return i
		}
	}
	return -1
}
