#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib
import subprocess, os, glob

PID_FILE = "/tmp/llama-server.pid"
LOG_FILE = "/opt/llamacpp-launcher/llama-server.log"
WRAPPER = "/opt/llamacpp-launcher/llama-server-wrapper.sh"
MODELS_DIR = "/opt/textgen/user_data/models"
CONFIG_FILE = "/opt/llamacpp-launcher/current_model.txt"


def is_running():
    try:
        with open(PID_FILE, "r") as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def run_cmd(args, env_extra=None):
    try:
        env = os.environ.copy()
        if env_extra:
            env.update(env_extra)
        result = subprocess.run(args, capture_output=True, text=True, timeout=60, env=env)
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"
    except Exception as e:
        return -1, "", str(e)


def notify(title, body):
    import subprocess as sp
    sp.run(["notify-send", title, body, "--icon=dialog-information", "--timeout=3000"], capture_output=True)


class LlamaServerWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Llama Server")
        self.set_border_width(20)
        self.set_default_size(520, 340)
        self.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        self.running = is_running()

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        vbox.set_margin_top(20); vbox.set_margin_bottom(20)
        vbox.set_margin_start(20); vbox.set_margin_end(20)

        # Titre
        title = Gtk.Label(); title.set_markup("<span weight='bold' size='large'>Llama.cpp Server</span>")
        title.set_halign(Gtk.Align.START); vbox.pack_start(title, False, False, 0)

        # --- Sélecteur de modèle ---
        model_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        model_label = Gtk.Label(label="Modèle :"); model_label.set_halign(Gtk.Align.START)
        model_box.pack_start(model_label, False, False, 0)
        self.model_combo = Gtk.ComboBoxText(); self.model_combo.set_hexpand(True)
        self._load_models(); model_box.pack_start(self.model_combo, True, True, 0)
        btn_refresh = Gtk.Button(label="Actualiser"); btn_refresh.connect("clicked", self.on_refresh_models)
        model_box.pack_start(btn_refresh, False, False, 0)
        btn_apply = Gtk.Button(label="Appliquer"); btn_apply.connect("clicked", self.on_apply_models)
        model_box.pack_start(btn_apply, False, False, 0)
        btn_params = Gtk.Button(label="Paramètres"); btn_params.connect("clicked", self.open_config_editor)
        model_box.pack_start(btn_params, False, False, 0)
        vbox.pack_start(model_box, False, False, 0)

        # Statut
        self.status_label = Gtk.Label(); self.status_label.set_markup(self._status_markup())
        self.status_label.set_halign(Gtk.Align.START); vbox.pack_start(self.status_label, False, False, 0)

        # Indicateur de sortie verbeuse
        self.log_label = Gtk.Label(); self.log_label.set_markup("<span size='small' color='#555555'><b>Sortie verbeuse :</b> En attente...</span>")
        self.log_label.set_halign(Gtk.Align.START); vbox.pack_start(self.log_label, False, False, 0)

        # --- Métriques GPU ---
        self.gpu_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.gpu_box.set_halign(Gtk.Align.CENTER)

        def make_row(name, bar, val):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            lbl = Gtk.Label()
            lbl.set_markup(f"<span size='small'>{name}</span>")
            lbl.set_size_request(70, 14)
            lbl.set_halign(Gtk.Align.START)
            row.pack_start(lbl, False, False, 0)
            bar.set_fraction(0.0)
            bar.set_size_request(200, 14)
            bar.set_text("")
            row.pack_start(bar, True, True, 0)
            val.set_markup("<span size='small'>—</span>")
            val.set_size_request(55, 14)
            val.set_halign(Gtk.Align.END)
            row.pack_start(val, False, False, 0)
            return row

        self.gpu_util_bar = Gtk.ProgressBar()
        self.gpu_util_val = Gtk.Label()
        self.gpu_box.pack_start(make_row("Utilisation", self.gpu_util_bar, self.gpu_util_val), False, False, 0)

        self.gpu_mem_bar = Gtk.ProgressBar()
        self.gpu_mem_val = Gtk.Label()
        self.gpu_box.pack_start(make_row("VRAM", self.gpu_mem_bar, self.gpu_mem_val), False, False, 0)

        self.gpu_temp_bar = Gtk.ProgressBar()
        self.gpu_temp_val = Gtk.Label()
        self.gpu_box.pack_start(make_row("Temp", self.gpu_temp_bar, self.gpu_temp_val), False, False, 0)

        vbox.pack_start(self.gpu_box, False, False, 0)
        GLib.timeout_add_seconds(2, self._refresh_gpu_timer)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL); vbox.pack_start(sep, False, False, 0)

        # Boutons Start/Stop
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10); btn_box.set_halign(Gtk.Align.CENTER)
        self.btn_start = Gtk.Button(label="Démarrer le serveur"); self.btn_start.set_hexpand(True); self.btn_start.connect("clicked", self.on_start); btn_box.pack_start(self.btn_start, True, True, 0)
        self.btn_stop = Gtk.Button(label="Arrêter le serveur"); self.btn_stop.set_hexpand(True); self.btn_stop.connect("clicked", self.on_stop); btn_box.pack_start(self.btn_stop, True, True, 0)
        vbox.pack_start(btn_box, False, False, 0)

        self.add(vbox); self._update_buttons()
        GLib.timeout_add_seconds(2, self._refresh_log_timer)
        self.connect("delete-event", self.on_close)

    def _load_models(self):
        self.model_combo.remove_all()
        models = sorted(glob.glob(os.path.join(MODELS_DIR, "*.gguf")))
        if not models: self.model_combo.append_text("Aucun modèle trouvé"); self.model_combo.set_sensitive(False); return
        for m in models: self.model_combo.append_text(m)
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, "r") as f: last = f.read().strip()
                if last in models: self.model_combo.set_active(models.index(last))
                else: self.model_combo.set_active(0)
            else: self.model_combo.set_active(0)
        except Exception: self.model_combo.set_active(0)

    def on_refresh_models(self, button):
        self._load_models()

    def _status_markup(self): return "<span color='green'><b>● En cours d'exécution</b></span>" if self.running else "<span color='red'><b>○ Arrêté</b></span>"

    def _update_buttons(self):
        self.btn_start.set_sensitive(not self.running)
        self.btn_stop.set_sensitive(self.running)
        self.status_label.set_markup(self._status_markup())
        self._update_log_indicator()

    def on_start(self, button):
        active = self.model_combo.get_active()
        if active < 0: return
        model_path = self.model_combo.get_active_text()
        if not model_path or not os.path.exists(model_path): return
        env_extra = {"MODEL_PATH": model_path}
        code, out, err = run_cmd([WRAPPER, "start"], env_extra=env_extra)
        GLib.timeout_add(1000, self._refresh_status)
        if code != 0:
            notify("Erreur", err or out)

    def on_stop(self, button):
        code, out, err = run_cmd([WRAPPER, "stop"])
        GLib.timeout_add(1000, self._refresh_status)
        if code != 0 and is_running():
            notify("Erreur", err or out)

    def on_apply_models(self, button):
        """Change de modèle : arrête, sauvegarde le nouveau, redémarre le tout en-place."""
        active = self.model_combo.get_active()
        if active < 0: return
        new_model = self.model_combo.get_active_text()
        if not new_model or not os.path.exists(new_model): return

        current = "inconnu"
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "r") as f: current = f.read().strip() or "inconnu"

        if new_model == current:
            notify("Info", "Déjà ce modèle"); return

        # On arrête le serveur
        self.on_stop(None)
        # Petite pause, puis on relance avec le nouveau modèle
        def delayed_start():
            run_cmd([WRAPPER, "start"], env_extra={"MODEL_PATH": new_model})
            return False

        def update_status():
            self._refresh_status()
            return False

        GLib.timeout_add(1000, delayed_start)
        GLib.timeout_add(2000, update_status)
        notify("Info", "Modèle changé pour " + os.path.basename(new_model))

    def open_config_editor(self, button):
        """Ouvre un éditeur pour modifier /opt/llamacpp-launcher/config.conf directement."""
        CONFIG_PATH = "/opt/llamacpp-launcher/config.conf"

        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            notify("Erreur", f"Impossible de lire {CONFIG_PATH}\n{e}")
            return

        dialog = Gtk.Dialog(title="Configuration - config.conf", transient_for=self,
                            flags=Gtk.DialogFlags.MODAL)
        dialog.set_default_size(600, 450)
        dialog.add_buttons("Annuler", Gtk.ResponseType.CANCEL,
                           "Sauvegarder", Gtk.ResponseType.OK)

        box = dialog.get_content_area()
        box.set_spacing(10)

        info = Gtk.Label()
        info.set_markup("<b>Modifiez le fichier de configuration ci-dessous :</b>")
        info.set_halign(Gtk.Align.START)
        box.pack_start(info, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        sw.set_hexpand(True); sw.set_vexpand(True)

        text_view = Gtk.TextView()
        text_view.set_monospace(True)
        buffer_ = text_view.get_buffer()
        buffer_.set_text(content)
        sw.add(text_view)

        box.pack_start(sw, True, True, 0)
        dialog.show_all()

        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            new_content = buffer_.get_text(buffer_.get_start_iter(), buffer_.get_end_iter(), True)
            try:
                # Sauvegarde propre avec préservation des commentaires/lignes vides
                with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                    f.write(new_content)
                notify("Configuration", "Fichier config.conf enregistré.\nRedémarrez le serveur pour appliquer les changements.")
                # Si le serveur tourne, on le redémarre pour appliquer les nouveaux paramètres
                if is_running():
                    self.on_stop(None)
                    GLib.timeout_add(1500, self.on_start, None)
            except Exception as e:
                notify("Erreur", f"Impossible d'écrire {CONFIG_PATH}\n{e}")

        dialog.destroy()

    def _update_log_indicator(self):
        try:
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, "r") as f: lines = f.read().splitlines()
                display = "\n".join(lines[-3:] if len(lines) >= 3 else lines[-1:] if lines else "")
                self.log_label.set_markup("<span size='x-small' color='#333333'><b>Sortie verbeuse :</b>\n" + display[-500:] + "</span>")
        except Exception: pass

    def _refresh_log_timer(self):
        self._update_log_indicator(); return True

    def _refresh_gpu_timer(self):
        self._update_gpu_indicator(); return True

    def _cpu_usage_percent(self):
        """Lecture CPU % depuis /proc/stat (sans externe)."""
        try:
            with open("/proc/stat", "r") as f:
                lines = f.read().splitlines()
            for line in lines:
                if line.startswith("cpu  "):
                    parts = line.split()[1:]
                    return float(sum(int(p) for p in parts[:2])) / 100.0 if False else float(sum(map(int, parts[:3]))) / max(1, sum(map(int, parts)) - sum(map(int, parts[:3])))
        except Exception:
            return None

    def _update_gpu_indicator(self):
        try:
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader"],
                capture_output=True, text=True, timeout=2
            )
            data_line = ""
            if result.returncode != 0 or not result.stdout.strip():
                # Défaillance : rien sur GPU
                pass
            else:
                lines = [l for l in result.stdout.strip().splitlines() if l.strip()]
                data_line = lines[-1] if len(lines) >= 1 else ""

            if not data_line:
                # Tenter AMD rocm-smi
                rmr = subprocess.run(
                    ["rocm-smi", "--showuse", "--showmeminfo", "--showtemp", "--json"],
                    capture_output=True, text=True, timeout=2
                )
                try:
                    import json as _j
                    arr = _j.loads(rmr.stdout) if rmr.stdout.strip() else {}
                    if arr and arr.get("gpu"):
                        item = list(arr["gpu"].values())[0]
                        util = float(item.get("Use", item.get("UseUtil", 0)))
                        mem_used = float(item.get("Mem.Used", 0))
                        mem_total = float(item.get("Mem.Total", 0))
                        temp = float(item.get("Temperature", item.get("Temps", 0)))
                        self.gpu_util_bar.set_fraction(max(util/100.0, 0.0))
                        self.gpu_util_val.set_markup(f"<span size='small'>{int(util)}%</span>")
                        self.gpu_mem_bar.set_fraction(min((mem_used/mem_total)*1.0 if mem_total>0 else 0, 1.0))
                        self.gpu_mem_val.set_markup(f"<span size='small'>{int(mem_used)} MiB / {int(mem_total)} MiB</span>")
                        self.gpu_temp_bar.set_fraction(min(temp/95.0,1.0) if temp>0 else 0.0)
                        self.gpu_temp_val.set_markup(f"<span size='small'>{int(temp)}°C</span>")
                        return
                except Exception:
                    pass

                self.gpu_util_bar.set_fraction(0.0)
                self.gpu_util_val.set_markup("<span size='small'>—</span>")
                self.gpu_mem_bar.set_fraction(0.0)
                self.gpu_mem_val.set_markup("<span size='small'>—</span>")
                self.gpu_temp_bar.set_fraction(0.0)
                self.gpu_temp_val.set_markup("<span size='small'>—</span>")
                return

            parts = [p.strip().replace("[","").replace("]","").replace("%","") for p in data_line.split(",")]

            def _to_num(s):
                """Convertir une chaîne comme '8192 MiB' -> 8192, '56' -> 56."""
                if not s: return 0.0
                digits = ''.join(c for c in s if c.isdigit())
                try: return float(digits) if digits else 0.0
                except Exception: return 0.0

            util = _to_num(parts[0]) if len(parts)>0 and parts[0] else 0
            mem_used_f = _to_num(parts[1]) if len(parts)>1 and parts[1] else 0
            mem_total_f = _to_num(parts[2]) if len(parts)>2 and parts[2] else 0
            temp_f = _to_num(parts[3]) if len(parts)>3 and parts[3] else 0

            self.gpu_util_bar.set_fraction(util/100.0)

            mem_frac = (mem_used_f/mem_total_f) if mem_total_f>0 else 0
            m_u = f"{mem_used_f/1024:.1f} Go" if mem_used_f>=1024 else f"{int(mem_used_f)} MiB"
            m_t = f"{mem_total_f/1024:.1f} Go" if mem_total_f>=1024 else f"{int(mem_total_f)} MiB"
            self.gpu_mem_bar.set_fraction(mem_frac)

            self.gpu_temp_bar.set_fraction(min(temp_f/95.0, 1.0) if temp_f>0 else 0.0)

            self.gpu_util_val.set_markup(f"<span size='small'>{int(util)}%</span>")
            self.gpu_mem_val.set_markup(f"<span size='small'>{m_u} / {m_t}</span>")
            self.gpu_temp_val.set_markup(f"<span size='small'>{int(temp_f)}°C</span>")

        except Exception:
            pass

    def _refresh_status(self):
        self.running = is_running(); self._update_buttons(); return False

    def on_close(self, widget, event):
        if is_running(): self.on_stop(None)
        Gtk.main_quit(); return True


def main():
    app = LlamaServerWindow(); app.show_all(); Gtk.main()


if __name__ == "__main__": main()