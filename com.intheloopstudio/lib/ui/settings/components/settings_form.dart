import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:formz/formz.dart';
import 'package:intheloopapp/domains/models/genre.dart';
import 'package:intheloopapp/domains/navigation_bloc/navigation_bloc.dart';
import 'package:intheloopapp/domains/navigation_bloc/tapped_route.dart';
import 'package:intheloopapp/ui/profile/components/epk_button.dart';
import 'package:intheloopapp/ui/settings/components/genre_selection.dart';
import 'package:intheloopapp/ui/settings/components/label_form_view.dart';
import 'package:intheloopapp/ui/settings/components/theme_switch.dart';
import 'package:intheloopapp/ui/settings/settings_cubit.dart';
import 'package:intheloopapp/ui/themes.dart';
import 'package:intheloopapp/utils/current_user_builder.dart';
import 'package:intheloopapp/utils/geohash.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsForm extends StatelessWidget {
  const SettingsForm({super.key});

  @override
  Widget build(BuildContext context) {
    return CurrentUserBuilder(
      builder: (context, currentUser) {
        return BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) {
            final cubit = context.read<SettingsCubit>();
            return Form(
              key: state.formKey,
              child: Column(
                children: [
                  // ── PROFILE ───────────────────────────────────────────
                  CupertinoFormSection.insetGrouped(
                    header: const Text('PROFILE'),
                    children: [
                      CupertinoTextFormFieldRow(
                        prefix: const Text('Username'),
                        placeholder: 'handle (no capitals)',
                        initialValue: state.username,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_\.]'),
                          ),
                        ],
                        validator: (input) {
                          if (input == null || input.trim().length < 2) {
                            return 'please enter a valid username';
                          }
                          return null;
                        },
                        onChanged: (input) {
                          if (input.isEmpty) return;
                          cubit.changeUsername(input.trim().toLowerCase());
                        },
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Text('Artist Name'),
                        placeholder: 'your artist name',
                        initialValue: state.artistName,
                        textAlign: TextAlign.end,
                        onChanged: cubit.changeArtistName,
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Text('Bio'),
                        placeholder: 'tell us about yourself',
                        initialValue: state.bio,
                        maxLines: 4,
                        textAlign: TextAlign.end,
                        validator: (input) {
                          if (input == null || input.trim().length < 2) {
                            return "bio can't be empty";
                          }
                          if (input.trim().length > 1024) {
                            return 'bio must be less than 1024 characters';
                          }
                          return null;
                        },
                        onChanged: cubit.changeBio,
                      ),
                      CupertinoFormRow(
                        prefix: const Text('Location'),
                        child: GestureDetector(
                          onTap: () => context.push(
                            LocationFormPage(
                              initialPlace: state.place,
                              onSelected: cubit.changePlace,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  state.place.match(
                                    () => 'Select a city',
                                    (t) => formattedShortAddress(
                                      t.addressComponents,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: state.place.isNone()
                                        ? CupertinoColors.placeholderText
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                CupertinoIcons.chevron_right,
                                size: 14,
                                color: CupertinoColors.systemGrey3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── SOCIAL MEDIA ──────────────────────────────────────
                  CupertinoFormSection.insetGrouped(
                    header: const Text('SOCIAL MEDIA'),
                    footer: GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://tappedapp.notion.site/how-do-i-get-my-spotify-url-2d1250547a044071becbe43763a77583',
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Text(
                              'How do I find my Spotify artist URL?',
                              style: TextStyle(
                                color: CupertinoColors.activeBlue,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.arrow_up_right_square,
                              color: CupertinoColors.activeBlue,
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                    children: [
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.xTwitter, size: 15),
                            SizedBox(width: 8),
                            Text('Twitter'),
                          ],
                        ),
                        placeholder: 'handle',
                        initialValue: state.twitterHandle,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_\.\-\$]'),
                          ),
                        ],
                        onChanged: (input) =>
                            cubit.changeTwitter(input.trim().toLowerCase()),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Text('  Twitter Followers'),
                        placeholder: '0',
                        initialValue: state.twitterFollowers?.toString(),
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.number,
                        onChanged: (input) => cubit.changeTwitterFollowers(
                          int.tryParse(input) ?? 0,
                        ),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.instagram, size: 15),
                            SizedBox(width: 8),
                            Text('Instagram'),
                          ],
                        ),
                        placeholder: 'handle',
                        initialValue: state.instagramHandle,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_\.\-\$]'),
                          ),
                        ],
                        onChanged: (input) =>
                            cubit.changeInstagram(input.trim().toLowerCase()),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Text('  Instagram Followers'),
                        placeholder: '0',
                        initialValue: state.instagramFollowers?.toString(),
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.number,
                        onChanged: (input) => cubit.changeInstagramFollowers(
                          int.tryParse(input) ?? 0,
                        ),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.tiktok, size: 15),
                            SizedBox(width: 8),
                            Text('TikTok'),
                          ],
                        ),
                        placeholder: 'handle',
                        initialValue: state.tiktokHandle,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_\.\-\$]'),
                          ),
                        ],
                        onChanged: (input) =>
                            cubit.changeTikTik(input.trim().toLowerCase()),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Text('  TikTok Followers'),
                        placeholder: '0',
                        initialValue: state.tiktokFollowers?.toString(),
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.number,
                        onChanged: (input) => cubit.changeTikTokFollowers(
                          int.tryParse(input) ?? 0,
                        ),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.youtube, size: 15),
                            SizedBox(width: 8),
                            Text('YouTube'),
                          ],
                        ),
                        placeholder: 'handle',
                        initialValue: state.youtubeHandle,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9_\.\-\$@]'),
                          ),
                        ],
                        onChanged: (input) => cubit.changeYoutube(input.trim()),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.soundcloud, size: 15),
                            SizedBox(width: 8),
                            Text('SoundCloud'),
                          ],
                        ),
                        placeholder: 'handle',
                        initialValue: state.soundcloudHandle,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_\.\-\$]'),
                          ),
                        ],
                        onChanged: (input) =>
                            cubit.changeSoundcloud(input.trim().toLowerCase()),
                      ),
                      CupertinoTextFormFieldRow(
                        prefix: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FaIcon(FontAwesomeIcons.spotify, size: 15),
                            SizedBox(width: 8),
                            Text('Spotify'),
                          ],
                        ),
                        placeholder: 'artist URL',
                        initialValue: state.spotifyUrl,
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.url,
                        onChanged: cubit.changeSpotify,
                      ),
                    ],
                  ),

                  // ── APPEARANCE ────────────────────────────────────────
                  CupertinoFormSection.insetGrouped(
                    header: const Text('APPEARANCE'),
                    children: [
                      CupertinoFormRow(
                        prefix: const Text('Theme'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: ThemeSwitch(),
                        ),
                      ),
                    ],
                  ),

                  // ── PERFORMER ─────────────────────────────────────────
                  CupertinoFormSection.insetGrouped(
                    header: const Text('PERFORMER'),
                    children: [
                      CupertinoFormRow(
                        prefix: const Text('I am a performer'),
                        child: CupertinoSwitch(
                          value: state.isPerformer,
                          onChanged: cubit.changeIsPerformer,
                        ),
                      ),
                      if (state.isPerformer) ...[
                        CupertinoFormRow(
                          prefix: const Text('Label'),
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<LabelFormView>(
                                builder: (context) => LabelFormView(
                                  onChange: cubit.changeLabel,
                                  initialValue: state.label,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  state.label != null && state.label != 'None'
                                      ? state.label!
                                      : 'Select a label',
                                  style: TextStyle(
                                    color: state.label == null ||
                                            state.label == 'None'
                                        ? CupertinoColors.placeholderText
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 14,
                                  color: CupertinoColors.systemGrey3,
                                ),
                              ],
                            ),
                          ),
                        ),
                        GenreSelection(
                          initialValue: state.genres,
                          onConfirm: (values) {
                            cubit.changeGenres(
                              values
                                  .where((e) => e != null)
                                  .whereType<Genre>()
                                  .toList(),
                            );
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: EPKButton(),
                        ),
                        if (state.status.isInProgress)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation(tappedAccent),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
