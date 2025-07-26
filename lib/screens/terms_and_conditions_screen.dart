import 'package:flutter/material.dart';
import '../core/supabase_client.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  static const String routeName = '/terms';
  const TermsAndConditionsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkAccountSuspended(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Terms & Conditions'),
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      _termsText,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _checkAccountSuspended(BuildContext context) async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return true;
      final doc = await SupabaseService.client.from('profiles').select().eq('id', user.id).single();
      if (doc == null) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Your account is suspended', style: TextStyle(color: Colors.white)),
            content: const Text('Your account has been suspended or deleted.', style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () async {
                  await SupabaseService.client.auth.signOut();
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                child: const Text('Log out', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  // You can replace this with loading from assets if needed
  static const String _termsText = '''
TalkTwirl Terms & Conditions (T&C)

Effective Date: 01-07-2025
Version: 1.0.2

 By using TalkTwirl, you (“User”) acknowledge and accept these legally binding Terms & Conditions (“Terms”). If you do not agree, you must discontinue use of the application and associated services.


1. Overview of TalkTwirl

TalkTwirl is a public and private social media platform operated for entertainment and communication purposes. Users can share media (photos, videos, twirls), text, and connect with other individuals.

By accessing or using TalkTwirl, you agree that:

You are at least 13 years of age

You will abide by the Community Guidelines

You will not use the platform to engage in any illegal or unethical activities


2. User Rights and Acceptable Use

You may use TalkTwirl to:

Create and maintain a personal account and profile

Share content that is legal, respectful, and appropriate

Report violations or content that appears harmful or abusive

Block or restrict unwanted interactions



3. Prohibited Content and Activities

The following are strictly prohibited and will result in immediate review, content removal, and/or account action:

A. Illegal or Unsafe Content

You may not post, distribute, or promote:

Nudity, pornography, or sexually explicit content (even if consensual)

Any content involving minors in a sexual or suggestive context (zero tolerance)

Deepfakes or AI-generated nudity of any person

Child sexual abuse material (CSAM)


B. Abuse and Harassment

You may not:

Harass, threaten, stalk, or cyberbully individuals

Incite violence, harm, or hate based on race, gender, orientation, nationality, religion, or disability

Encourage suicide, self-harm, eating disorders, or substance abuse


C. Identity and Deception

You may not:

Create fake or impersonated profiles

Share misleading, doctored, or AI-altered content meant to deceive

Impersonate public figures, law enforcement, or TalkTwirl staff


D. Exploitation or Criminal Use

You may not:

Use the platform for grooming, trafficking, blackmail, or extortion

Engage in sextortion, threats over shared content, or revenge pornography

Monetize inappropriate content through third-party tools


4. Moderation, AI & Enforcement

TalkTwirl uses a combination of human moderation and automated AI tools to detect harmful or prohibited content. Actions include:

Immediate content suppression

Shadowbanning abusive accounts

Reporting to authorities (when applicable)

Preserving evidence for legal investigations


Enforcement Levels:

Violation Count	Action Taken

1st	Warning (email/app notification)
2nd	Temporary ban (7–30 days)
3rd	Permanent ban and device/IP block
Severe Cases	Instant ban + law enforcement report



5. 🛡 Privacy, Security & Legal Access

A. User Privacy

Private chats are encrypted with end-to-end security

TalkTwirl does not sell your data to third parties


B. Safety Overrides

We reserve the right to decrypt and review reported or flagged content only when:

Required by law enforcement

Necessary to prevent immediate harm, suicide, or abuse

Requested via court orders, subpoenas, or government requests


C. Legal Cooperation

We will cooperate fully with any official investigation regarding misuse, harassment, or any form of criminal activity involving our platform.



6. Underage Use

Minimum usage age: 13 years

Users under 18 should use the platform under guidance of a parent/guardian

Accounts found belonging to minors sharing explicit content will be deleted and may be escalated to child protection agencies



7. Reporting System

Users can report:

Profiles

Posts

Comments

Private messages


All reports are reviewed within 48 hours. For emergencies (e.g., harm, threats, minors in danger), email: talktwirl.help@gmail.com.


8. ⚖ Legal Liability & Disclaimer

TalkTwirl is not responsible for:

Actions of users on or off the platform

Content viewed, shared, or downloaded by users

Any personal harm, loss, or legal dispute arising from user interaction

In-app purchases or financial losses due to fraud/scams by third-party users


Users are solely responsible for their content and interactions.


9. Intellectual Property & Content Rights

All original content remains the property of its creator

By posting, you grant TalkTwirl a non-exclusive, royalty-free license to display and distribute your content on the platform

Content copied or stolen from third parties is not permitted



10. 🛠 Platform Policy Updates

We may update these Terms at any time to comply with:

Local and international laws

Platform safety standards

User feedback and risk assessments


Significant changes will be communicated via in-app notification and/or email.



11. Escalation & Emergency Contacts

If you believe someone is in danger, experiencing abuse, or facing mental health crises, please report immediately.

In life-threatening cases, contact local law enforcement before contacting TalkTwirl.



12. Contact

Email: talktwirl.help@gmail.com


 User Acknowledgement

By signing up and continuing to use TalkTwirl, you acknowledge:

> “I understand and agree to abide by TalkTwirl’s Terms & Conditions and Community Guidelines. I am fully responsible for my actions on the platform.”



 Developer / Owner Note (Optional for internal use)

> This T&C shields the platform against nudity/harassment legal cases by proactively:

Warning users

Implementing AI + human moderation

Cooperating with police

Rejecting liability for user actions

Enforcing age and consent policies

Holding power to ban, delete, or report users"
''';
}
