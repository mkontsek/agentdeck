import Foundation

/// An isolated provider-protocol fixture. No prompt is ever evaluated as code or sent to a shell.
enum ResumeProtocolFixture {
    static func write(directory: URL, threadID: String, mode: String = "happy") throws -> String {
        let metadata =
            ["id": threadID, "cwd": directory.path, "status": ["type": mode == "active" ? "active" : "idle"]]
            as [String: Any]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
        let script = """
            #!/usr/bin/ruby
            require 'json'
            require 'digest'
            require 'base64'
            STDOUT.sync = true
            mode = '\(mode)'
            if mode == 'stuck'
              Signal.trap('TERM', 'IGNORE')
              File.write('\(directory.appendingPathComponent("fixture.pid").path)', Process.pid.to_s)
            end
            metadata = JSON.parse(<<'METADATA')
            \(json)
            METADATA
            header = ''
            while !header.end_with?("\\r\\n\\r\\n")
              byte = STDIN.read(1)
              exit unless byte
              header += byte
            end
            key = header[/Sec-WebSocket-Key: (.*)\\r/,1]
            accept = Base64.strict_encode64(Digest::SHA1.digest(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
            STDOUT.write("HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\nSec-WebSocket-Accept: " + accept + "\\r\\n\\r\\n")
            def frame(object)
              bytes = JSON.generate(object).bytes
              head = [129]
              if bytes.length < 126
                head << bytes.length
              else
                head += [126, bytes.length >> 8, bytes.length & 255]
              end
              STDOUT.write((head+bytes).pack('C*'))
            end
            while first = STDIN.read(2)
              break if first.length < 2
              length = first.bytes[1] & 127
              length = STDIN.read(2).unpack1('n') if length == 126
              length = STDIN.read(8).unpack1('Q>') if length == 127
              mask = STDIN.read(4).bytes
              bytes = STDIN.read(length).bytes.each_with_index.map { |b,i| b ^ mask[i%4] }
              message = JSON.parse(bytes.pack('C*'))
              next unless message['id']
              File.open('\(directory.appendingPathComponent("protocol.jsonl").path)', 'a') { |f| f.puts(JSON.generate(message)) }
              method = message['method']
              params = message['params'] || {}
              result = {}
              case method
              when 'thread/read', 'thread/resume'
                sleep 0.15 if mode == 'slow'
                result = {'thread'=>metadata}
              when 'thread/queue/add'
                exit if mode == 'lost-acceptance'
                result = {'queuedSubmission'=>{'id'=>'queue97','clientUserMessageId'=>params['clientUserMessageId']}}
              when 'thread/queue/start'
                if mode == 'race'
                  frame({'id'=>message['id'],'error'=>{'message'=>'thread is already active'}})
                  next
                end
                sleep 5 if mode == 'cancel-queued'
                result = {'turn'=>{'id'=>'turn97','status'=>'inProgress'}}
              when 'thread/queue/delete'
                result = {'deleted'=>true}
              when 'thread/queue/list'
                result = {'data'=>[], 'nextCursor'=>nil}
              end
              frame({'id'=>message['id'],'result'=>result})
              if method == 'thread/queue/start' && mode != 'running'
                frame({'method'=>'turn/completed','params'=>{'threadId'=>metadata['id'],'turn'=>{'id'=>'turn97','status'=>'completed'}}})
              end
            end
            # A stuck proxy outlives stdin EOF and SIGTERM. The bound ends a fixture abandoned by a failed runner.
            sleep 20 if mode == 'stuck'
            """
        let url = directory.appendingPathComponent("provider-fixture")
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
}
