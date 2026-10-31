// Temporion x86 — thin GNOME Shell frontend.
//
// This file exists only because GNOME Shell extensions must have a GJS entry
// point. All sensor logic lives in the `temporion-x86d` assembly daemon. Here we simply launch it and read its stdout
// lines *asynchronously*, so the compositor main loop never does blocking I/O
// (which is exactly what makes freon stutter).

import GObject from 'gi://GObject';
import St from 'gi://St';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Replaced with an absolute /nix/store path by the flake at build time.
const DAEMON_PATH = '@TEMPORION_X86D@';

// Index in the panel's left box: 0 is the workspace indicator, so 1 puts us
// right after "the workspace thing".
const PANEL_POSITION = 1;

// Colour thresholds in °C (generic across sensors; tweak to taste).
const WARN_C = 75;
const HOT_C = 90;

const NORMAL_STYLE = '';
const WARN_STYLE = 'color: #f5c211;';
const HOT_STYLE = 'color: #ed333b; font-weight: bold;';
const IDLE_STYLE = 'opacity: 0.45;';

function tagFor(index) {
    if (index === 0)
        return 'CPU';
    if (index === 1)
        return 'GPU';
    return `D${index - 2}`;
}

const TemporionX86Indicator = GObject.registerClass({GTypeName: 'TemporionX86Indicator'},
class TemporionX86Indicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Temporion x86', true /* dontCreateMenu */);
        this.reactive = false; // passive readout, no click menu

        this._box = new St.BoxLayout({style_class: 'temporion-x86-box'});
        this.add_child(this._box);

        this._items = []; // { value: St.Label }
    }

    // Rebuild the label set when the field count changes.
    _rebuild(count) {
        this._box.destroy_all_children();
        this._items = [];
        for (let i = 0; i < count; i++) {
            const item = new St.BoxLayout({style_class: 'temporion-x86-item'});
            item.add_child(new St.Label({
                style_class: 'temporion-x86-tag',
                text: tagFor(i),
                y_align: 2, // CENTER
            }));
            const value = new St.Label({
                style_class: 'temporion-x86-value',
                text: '–',
                y_align: 2, // CENTER
            });
            item.add_child(value);
            this._box.add_child(item);
            this._items.push({value});
        }
    }

    update(parts) {
        if (parts.length !== this._items.length)
            this._rebuild(parts.length);

        for (let i = 0; i < parts.length; i++) {
            const label = this._items[i].value;
            const part = parts[i];
            if (part === '-') {
                label.text = '–';
                label.set_style(IDLE_STYLE);
                continue;
            }
            const celsius = parseInt(part, 10);
            label.text = `${part}°`;
            if (Number.isNaN(celsius))
                label.set_style(IDLE_STYLE);
            else if (celsius >= HOT_C)
                label.set_style(HOT_STYLE);
            else if (celsius >= WARN_C)
                label.set_style(WARN_STYLE);
            else
                label.set_style(NORMAL_STYLE);
        }
    }
});

export default class TemporionX86Extension extends Extension {
    enable() {
        this._indicator = new TemporionX86Indicator();
        Main.panel.addToStatusArea('temporion-x86', this._indicator, PANEL_POSITION, 'left');

        this._cancellable = new Gio.Cancellable();
        this._restartId = 0;
        this._startDaemon();
    }

    disable() {
        if (this._restartId) {
            GLib.source_remove(this._restartId);
            this._restartId = 0;
        }
        if (this._cancellable) {
            this._cancellable.cancel();
            this._cancellable = null;
        }
        if (this._proc) {
            try {
                this._proc.force_exit();
            } catch (_e) {
                // already gone
            }
            this._proc = null;
        }
        this._stdout = null;
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }

    _daemonArgv() {
        if (!DAEMON_PATH.startsWith('@'))
            return [DAEMON_PATH];
        // Manual (non-Nix) install: fall back to PATH lookup.
        const found = GLib.find_program_in_path('temporion-x86d');
        return [found ?? 'temporion-x86d'];
    }

    _startDaemon() {
        try {
            this._proc = new Gio.Subprocess({
                argv: this._daemonArgv(),
                flags: Gio.SubprocessFlags.STDOUT_PIPE,
            });
            this._proc.init(this._cancellable);
        } catch (e) {
            logError(e, 'Temporion x86: failed to launch temporion-x86d');
            this._scheduleRestart();
            return;
        }

        this._stdout = new Gio.DataInputStream({
            base_stream: this._proc.get_stdout_pipe(),
        });
        this._readNextLine();
    }

    _readNextLine() {
        if (!this._stdout || !this._cancellable)
            return;

        this._stdout.read_line_async(GLib.PRIORITY_DEFAULT, this._cancellable, (stream, res) => {
            let line;
            try {
                [line] = stream.read_line_finish_utf8(res);
            } catch (e) {
                if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    this._scheduleRestart();
                return;
            }

            if (line === null) {
                // EOF: the daemon exited. Restart it after a short delay.
                this._scheduleRestart();
                return;
            }

            const parts = line.trim().split(/\s+/).filter(p => p.length > 0);
            if (parts.length > 0)
                this._indicator?.update(parts);

            this._readNextLine();
        });
    }

    _scheduleRestart() {
        if (!this._cancellable || this._restartId)
            return; // shutting down, or a restart is already queued

        if (this._proc) {
            try {
                this._proc.force_exit();
            } catch (_e) {
                // already gone
            }
            this._proc = null;
        }
        this._stdout = null;

        this._restartId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
            this._restartId = 0;
            if (this._cancellable)
                this._startDaemon();
            return GLib.SOURCE_REMOVE;
        });
    }
}
