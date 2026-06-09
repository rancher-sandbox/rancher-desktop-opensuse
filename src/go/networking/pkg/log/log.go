package log

/*
Copyright © 2023 SUSE LLC
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import (
	"os"

	"github.com/sirupsen/logrus"
)

const fileMode = 0o666

// SetOutputFile points the logger at filePath. When appendMode is true the file
// is opened for appending, so its contents survive a process restart; otherwise
// the file is truncated on open.
func SetOutputFile(filePath string, appendMode bool, logger *logrus.Logger) error {
	flags := os.O_WRONLY | os.O_CREATE | os.O_TRUNC
	if appendMode {
		flags = os.O_WRONLY | os.O_CREATE | os.O_APPEND
	}
	logFile, err := os.OpenFile(filePath, flags, fileMode)
	if err != nil {
		return err
	}
	logger.SetOutput(logFile)

	return nil
}
