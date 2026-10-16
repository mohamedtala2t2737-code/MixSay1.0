import 'package:flutter/material.dart';

import 'package:social_chat/core/config/chat_features.dart';
import 'package:social_chat/core/l10n/app_strings.dart';
import 'package:social_chat/core/theme/app_colors.dart';

/// The composer: one rounded field holding the panel button at its start and
/// the attach and camera icons at its end, with a single round button beside it.
///
/// Every control here comes from a flag or from what the field holds, so a
/// disabled feature does not leave a greyed icon on screen — it leaves nothing.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.trayAvailable,
    required this.attachAvailable,
    required this.cameraAvailable,
    required this.micAvailable,
    required this.trayOpen,
    required this.busy,
    required this.onTrayTap,
    required this.onAttachTap,
    required this.onCameraTap,
    required this.onMicTap,
    required this.onSend,
    required this.onTextChanged,
    this.inFlight,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  final bool trayAvailable;
  final bool attachAvailable;
  final bool cameraAvailable;

  /// Whether a voice note can be recorded in this build. An empty field with no
  /// voice to record leaves the round button off the screen entirely.
  final bool micAvailable;
  final bool trayOpen;

  /// True while a send is in progress: the round button spins and nothing else
  /// accepts a tap.
  final bool busy;

  final VoidCallback onTrayTap;
  final VoidCallback? onAttachTap;
  final VoidCallback? onCameraTap;
  final VoidCallback? onMicTap;
  final VoidCallback onSend;
  final ValueChanged<String> onTextChanged;

  /// A take or upload that is already running. It takes the field's place, so
  /// its own cancel and send controls are the only ones on screen.
  final Widget? inFlight;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final brightness = Theme.of(context).brightness;
    // The round button changes shape with the field, so the field is what this
    // widget listens to — nothing else on the screen needs to rebuild for it.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasText = controller.text.trim().isNotEmpty;
        // An empty field has nothing to send, so the button becomes the mic when
        // a note can be recorded, and is not drawn when it cannot.
        final asMicrophone = !hasText && micAvailable;
        final running = inFlight;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (trayAvailable)
              IconButton(
                tooltip: trayOpen ? strings.closeChatPanel : strings.emoji,
                onPressed: onTrayTap,
                icon: Icon(
                  trayOpen
                      ? Icons.keyboard_outlined
                      : Icons.emoji_emotions_outlined,
                ),
              ),
            if (running != null)
              Expanded(child: running)
            else ...[
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                  decoration: BoxDecoration(
                    color: AppColors.fieldFill(brightness),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _field(context, strings)),
                      if (attachAvailable)
                        IconButton(
                          tooltip: strings.attach,
                          onPressed: busy ? null : onAttachTap,
                          icon: const Icon(Icons.attach_file),
                        ),
                      if (cameraAvailable)
                        IconButton(
                          tooltip: strings.takePhoto,
                          onPressed: busy ? null : onCameraTap,
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                    ],
                  ),
                ),
              ),
              if (hasText || micAvailable) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    tooltip: asMicrophone ? strings.recordVoice : strings.send,
                    onPressed: busy ? null : (asMicrophone ? onMicTap : onSend),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.chatActionGreen,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                    icon: busy && !asMicrophone
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            asMicrophone
                                ? Icons.mic_outlined
                                : Icons.send_rounded,
                          ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  /// The field itself: no border and no fill of its own, because the rounded
  /// pill around it is what makes it look like one box.
  Widget _field(BuildContext context, AppStrings strings) => TextField(
    controller: controller,
    focusNode: focusNode,
    minLines: 1,
    maxLines: 5,
    maxLength: ChatFeatures.maxTextLength,
    textCapitalization: TextCapitalization.sentences,
    onChanged: onTextChanged,
    onSubmitted: (_) => onSend(),
    buildCounter:
        (
          context, {
          required currentLength,
          required isFocused,
          required maxLength,
        }) => currentLength >= 3900
        ? Text(
            strings.messageCharacterCount(
              currentLength,
              maxLength ?? ChatFeatures.maxTextLength,
            ),
            style: Theme.of(context).textTheme.labelSmall,
          )
        : null,
    decoration: InputDecoration(
      hintText: strings.typeMessage,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      isDense: true,
    ),
  );
}
