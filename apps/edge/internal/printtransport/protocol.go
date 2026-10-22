package printtransport

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"unicode/utf16"
	"unicode/utf8"
)

const HelperProtocolVersion uint16 = 1
const helperMagic uint32 = 0x31505456
const maxFrameBytes = 16 * 1024 * 1024
const (
	tagInventory       byte = 1
	tagSubmit          byte = 2
	tagCommit          byte = 3
	tagReady           byte = 64
	tagResult          byte = 65
	tagInventoryResult byte = 66
)

type QueueDescriptor struct {
	Name   string `json:"name"`
	Driver string `json:"driver"`
	Port   string `json:"port"`
}

func header(tag byte) []byte {
	frame := make([]byte, 8)
	binary.LittleEndian.PutUint32(frame, helperMagic)
	binary.LittleEndian.PutUint16(frame[4:], HelperProtocolVersion)
	frame[6] = tag
	return frame
}

func appendText(frame []byte, value string) []byte {
	frame = binary.LittleEndian.AppendUint32(frame, uint32(len(value)))
	return append(frame, value...)
}

func submissionFrame(d Destination, payload []byte, guard string) []byte {
	frame := header(tagSubmit)
	for _, value := range []string{d.QueueName, d.ExpectedDriverName, d.ExpectedPortName, d.DocumentName, guard} {
		frame = appendText(frame, value)
	}
	frame = binary.LittleEndian.AppendUint32(frame, uint32(len(payload)))
	return append(frame, payload...)
}

func writeFrame(writer io.Writer, frame []byte) error {
	if len(frame) < 8 || len(frame) > maxFrameBytes {
		return errors.New("helper frame exceeds bounds")
	}
	encoded := binary.LittleEndian.AppendUint32(nil, uint32(len(frame)))
	encoded = append(encoded, frame...)
	for len(encoded) != 0 {
		count, err := writer.Write(encoded)
		if count < 0 || count > len(encoded) {
			return errors.New("invalid helper pipe write count")
		}
		encoded = encoded[count:]
		if err != nil {
			return err
		}
		if count == 0 {
			return io.ErrShortWrite
		}
	}
	return nil
}

func readFrame(reader io.Reader) ([]byte, error) {
	var prefix [4]byte
	if _, err := io.ReadFull(reader, prefix[:]); err != nil {
		return nil, err
	}
	size := binary.LittleEndian.Uint32(prefix[:])
	if size < 8 || size > maxFrameBytes {
		return nil, errors.New("helper frame exceeds bounds")
	}
	frame := make([]byte, int(size))
	if _, err := io.ReadFull(reader, frame); err != nil {
		return nil, err
	}
	if binary.LittleEndian.Uint32(frame) != helperMagic || binary.LittleEndian.Uint16(frame[4:]) != HelperProtocolVersion || frame[7] != 0 {
		return nil, errors.New("helper protocol/version mismatch")
	}
	return frame, nil
}

type wireReader struct{ *bytes.Reader }

func (r wireReader) u32() (uint32, error) {
	var value uint32
	err := binary.Read(r.Reader, binary.LittleEndian, &value)
	return value, err
}

func (r wireReader) text(maxUnits int, allowEmpty, visible bool) (string, error) {
	size, err := r.u32()
	if err != nil || size > uint32(maxUnits*4) || uint64(size) > uint64(r.Len()) {
		return "", errors.New("helper text exceeds bounds")
	}
	value := make([]byte, int(size))
	if _, err = io.ReadFull(r.Reader, value); err != nil {
		return "", err
	}
	text := string(value)
	if !utf8.ValidString(text) || text == "" && !allowEmpty {
		return "", errors.New("invalid helper UTF-8 text")
	}
	units, hasVisible := 0, false
	for _, c := range text {
		if c < 32 || c == 127 {
			return "", errors.New("helper text contains control characters")
		}
		units += utf16.RuneLen(c)
		hasVisible = hasVisible || c > 32
	}
	if units > maxUnits || visible && text != "" && !hasVisible {
		return "", errors.New("helper text exceeds UTF-16 units or has no visible content")
	}
	return text, nil
}

func decodeResult(frame []byte, expectedBytes int) (Result, error) {
	if len(frame) < 24 || frame[6] != tagResult {
		return Result{}, errors.New("unexpected helper result")
	}
	if frame[8] > 2 || frame[9] > 1 || binary.LittleEndian.Uint16(frame[10:]) != 0 {
		return Result{}, errors.New("invalid helper result fields")
	}
	r := wireReader{bytes.NewReader(frame[12:])}
	count, err := r.u32()
	if err != nil {
		return Result{}, err
	}
	job, err := r.u32()
	if err != nil {
		return Result{}, err
	}
	code, err := r.u32()
	if err != nil {
		return Result{}, err
	}
	stage, err := r.text(64, false, true)
	if err != nil {
		return Result{}, err
	}
	detail, err := r.text(2048, true, true)
	if err != nil {
		return Result{}, err
	}
	if r.Len() != 0 || count > uint32(expectedBytes) {
		return Result{}, errors.New("extra or inconsistent helper result fields")
	}
	states := []State{NotSent, Submitted, Uncertain}
	result := Result{State: states[frame[8]], WriteAttempted: frame[9] == 1, BytesWritten: count, JobID: job, WindowsError: code, Stage: stage, Detail: detail}
	if result.State == NotSent && (result.WriteAttempted || count != 0 || job != 0) || result.State == Submitted && (!result.WriteAttempted || job == 0 || count != uint32(expectedBytes)) || result.State == Uncertain && !result.WriteAttempted {
		return Result{}, errors.New("helper outcome contradicts attempt evidence")
	}
	return result, nil
}

func decodeInventory(frame []byte) ([]QueueDescriptor, error) {
	if len(frame) < 12 || frame[6] != tagInventoryResult {
		return nil, errors.New("unexpected helper inventory")
	}
	r := wireReader{bytes.NewReader(frame[8:])}
	count, err := r.u32()
	if err != nil || count > 1024 {
		return nil, errors.New("helper inventory exceeds bounds")
	}
	queues := make([]QueueDescriptor, 0, int(count))
	for n := uint32(0); n < count; n++ {
		name, err := r.text(255, false, true)
		if err != nil {
			return nil, err
		}
		driver, err := r.text(1024, true, false)
		if err != nil {
			return nil, err
		}
		port, err := r.text(1024, true, false)
		if err != nil {
			return nil, err
		}
		queues = append(queues, QueueDescriptor{name, driver, port})
	}
	if r.Len() != 0 {
		return nil, errors.New("extra helper inventory fields")
	}
	return queues, nil
}
