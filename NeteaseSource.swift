import Cocoa

// ---------------------------------------------------------------------------
// 播放数据源：网易云音乐客户端（CEF 调试端口）
//
// 客户端是 CEF 架构，不向系统注册 Now Playing，MediaRemote 读不到。但它是自绘
// 播放器（页面里没有真实的 <audio>），所有状态都落在页面 DOM 上，于是用客户端
// 自带的远程调试端口走 CDP 取值（通信在 CDPClient，通用逻辑在 CDPPlayerSource）：
//   - 歌名 / 歌手：footer 里 [data-testid="tid_minibar_title"] 的 .main-title 与 .author
//   - 进度 / 时长：footer 里 input[type=range] 的 value 与 max（单位秒）
//   - 播放状态：footer 内 [aria-label] 为 pause（播放中）或 play（已暂停）
//   - 封面：footer 内 img 的 src，形如 orpheus://cache/?http://pN.music.126.net/...
// 控制走同一页面上的按钮节点，跳到指定秒数则在进度条上派发指针事件。
// （以上选择器于 2026-11-03 在网易云 3.1.12 上逐条实测，与 AGENTS.md 第 4 节同步）
//
// 端口只在客户端以 --remote-debugging-port=9222 启动时存在。2026-11-03 用户改口径：
// 岛启动时若客户端没跑，由岛带端口拉起；已在跑却没端口时，主页给一行可点的重启入口
// （见 PlayerLauncher 与 MediaStore.portNotice）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

extension CDPPlayerProfile {
    /// 网易云（com.netease.163music）：选择器改动只动这里
    static let netease = CDPPlayerProfile(
        bundleID: "com.netease.163music",
        debugPort: 9222,
        probeJS: #"""
        (function(){
          var f = document.querySelector('footer');
          if (!f) return '';
          var box = f.querySelector('[data-testid="tid_minibar_title"]');
          var range = f.querySelector('input[type=range]');
          if (!box || !range) return '';
          var main = box.querySelector('.main-title');
          var author = box.querySelector('.author');
          var title = main ? (main.textContent || '').trim() : '';
          if (!title) return '';
          var img = f.querySelector('img');
          var cover = img ? String(img.getAttribute('src') || '') : '';
          if (cover.indexOf('http') > 0) cover = cover.slice(cover.indexOf('http'));
          cover = cover.replace('http://', 'https://').replace(/thumbnail=\d+y\d+/, 'thumbnail=200y200');
          var state = f.querySelector('[aria-label="play"], [aria-label="pause"]');
          return JSON.stringify({
            title: title,
            artist: author ? (author.textContent || '').trim() : '',
            cover: cover,
            pos: parseFloat(range.value) || 0,
            dur: parseFloat(range.max) || 0,
            playing: state ? state.getAttribute('aria-label') === 'pause' : false
          });
        })()
        """#,
        toggleJS: #"""
        (function(){
          var b = document.querySelector('[data-testid="tid_playbar_play_btn"]');
          if (b) b.click();
        })()
        """#,
        nextJS: #"""
        (function(){
          var b = document.querySelector('[data-testid="tid_playbar_next_btn"]');
          if (b) b.click();
        })()
        """#,
        previousJS: #"""
        (function(){
          var b = document.querySelector('[data-testid="tid_playbar_prev_btn"]');
          if (b) b.click();
        })()
        """#,
        // 按秒数换算成进度条比例后派发指针事件；用真实坐标点，不直接改 input.value，
        // 因为这个 range 只是无障碍外壳，真正接管交互的是外层自绘滑块
        seekJS: { seconds in
            let safe = max(0, seconds)
            return """
            (function(sec){
              var f = document.querySelector('footer');
              if (!f) return '';
              var bar = f.querySelector('[aria-label="播放进度调节"]');
              var range = f.querySelector('input[type=range]');
              if (!bar || !range) return '';
              var max = parseFloat(range.max) || 0;
              if (!(max > 0)) return '';
              var ratio = Math.max(0, Math.min(1, sec / max));
              var track = bar.querySelector('.cache') || bar;
              var r = track.getBoundingClientRect();
              if (r.width <= 0) return '';
              var o = {bubbles:true, cancelable:true, clientX:r.left + r.width * ratio,
                       clientY:r.top + r.height / 2, view:window, button:0, buttons:1,
                       pointerId:1, pointerType:'mouse', isPrimary:true};
              track.dispatchEvent(new PointerEvent('pointerdown', o));
              track.dispatchEvent(new MouseEvent('mousedown', o));
              document.dispatchEvent(new PointerEvent('pointerup', o));
              document.dispatchEvent(new MouseEvent('mouseup', o));
              return 'ok';
            })(\(safe))
            """
        },
        // 实测 3.1.12：普通方式打开时主进程 argv 里没有该参数，9222 不监听，
        // 所以由岛负责带端口拉起（见 PlayerLauncher）
        preparesPortOnLaunch: true
    )
}

final class NeteaseSource: CDPPlayerSource {
    init() {
        super.init(profile: .netease)
    }
}