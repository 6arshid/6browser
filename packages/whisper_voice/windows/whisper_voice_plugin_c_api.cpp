#include "include/whisper_voice/whisper_voice_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "whisper_voice_plugin.h"

void WhisperVoicePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  whisper_voice::WhisperVoicePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
