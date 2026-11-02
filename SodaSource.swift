import Cocoa

// ---------------------------------------------------------------------------
// 播放数据源：汽水音乐（com.soda.music）
//
// 结构上是 Electron（有 Electron Framework / app.asar，走 CDP 的那一套），但本机装的是
// **App Store 沙盒版**，2026-11-03 实测：
//   - `open -a ... --args --remote-debugging-port=9333` 与直接跑 Contents/MacOS 主程序
//     两种方式都拿不到端口：进程 ps 里 argv 被清空（启动日志有 "MAS 环境禁用小包更新"，
//     主进程会再拉起一个自己），日志明确报 "Most NODE_OPTIONs are not supported in
//     packaged apps"，无任何 LISTEN 命中 9000–9500。
//   - `lsof` 全程没有该进程的监听口，`/json/list` 连不上。
// 所以这一家当前读不到内容。按用户 2026-11-03 的口径（读不到就整块不显示、不提示、
// 不重启、不杀进程）它只会恒返回空快照，不影响其它家。
//
// 保留这个文件的价值：探针用的是「mediaSession 元数据 + <audio> 元素」的通用写法，
// 若某天装上接受 --remote-debugging-port 的版本（内测/官网 dmg），只需把端口对上即可，
// 不用重写通道。选择器不做猜测性点击，控制只走 audio 元素，避免发出错误操作。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

extension CDPPlayerProfile {
    /// 汽水音乐（com.soda.music）：端口与通用探针
    static let soda = CDPPlayerProfile(
        bundleID: "com.soda.music",
        debugPort: 9333,
        probeJS: #"""
        (function(){
          var ms = navigator.mediaSession && navigator.mediaSession.metadata;
          var a = document.querySelector('audio');
          if (!ms && !a) return '';
          var title = (ms && ms.title) ? ms.title : (document.title || '');
          if (!title) return '';
          var artist = (ms && ms.artist) ? ms.artist : '';
          var cover = '';
          if (ms && ms.artwork && ms.artwork.length) {
            cover = String(ms.artwork[ms.artwork.length - 1].src || '');
          }
          return JSON.stringify({
            title: title,
            artist: artist,
            cover: cover,
            pos: a ? (a.currentTime || 0) : 0,
            dur: (a && isFinite(a.duration)) ? a.duration : 0,
            playing: a ? !a.paused : false
          });
        })()
        """#,
        toggleJS: #"""
        (function(){
          var a = document.querySelector('audio');
          if (!a) return '';
          if (a.paused) a.play(); else a.pause();
          return 'ok';
        })()
        """#,
        // 上下首没有可靠的无损入口（页面按钮无稳定标识，mediaSession 的 action handler
        // 不能从外部触发），宁可不做也不乱点，返回空串即「未执行」
        nextJS: "",
        previousJS: "",
        seekJS: { seconds in
            let safe = max(0, seconds)
            return """
            (function(sec){
              var a = document.querySelector('audio');
              if (!a || !isFinite(a.duration)) return '';
              a.currentTime = Math.max(0, Math.min(a.duration, sec));
              return 'ok';
            })(\(safe))
            """
        }
    )
}

final class SodaSource: CDPPlayerSource {
    init() {
        super.init(profile: .soda)
    }
}