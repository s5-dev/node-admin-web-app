import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:filesize/filesize.dart';
import 'package:pasteboard/pasteboard.dart';

final httpClient = http.Client();

const adminApiBaseUrl = '/s5/admin';
String? adminApiKey;

Map<String, String> get headers => {
      'Authorization': 'Bearer $adminApiKey',
    };

late Box authBox;

void main() async {
  if (!kIsWeb) {
    Hive.init('data');
  }
  authBox = await Hive.openBox('auth');
  adminApiKey = authBox.get('admin_api_key');

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final adminApiKeyTextCtrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // theme: ThemeData.dark(),
      theme: ThemeData(
          inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(),
      )),
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            'S5 Node Admin UI',
          ),
          actions: [
            if (adminApiKey != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ElevatedButton(
                    style: ButtonStyle(
                      backgroundColor: MaterialStatePropertyAll(
                        Colors.red,
                      ),
                    ),
                    onPressed: () {
                      authBox.delete('admin_api_key');
                      setState(() {
                        adminApiKey = null;
                      });
                    },
                    child: Text(
                      'Sign out',
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: adminApiKey == null
            ? Center(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Admin API Key',
                        ),
                        controller: adminApiKeyTextCtrl,
                        autofocus: true,
                      ),
                      SizedBox(
                        height: 16,
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            adminApiKey = adminApiKeyTextCtrl.text;
                          });
                          adminApiKeyTextCtrl.clear();
                          authBox.put('admin_api_key', adminApiKey);
                        },
                        child: Text(
                          'Authenticate',
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : AccountsView(),
      ),
    );
  }
}

void showErrorDialog(BuildContext context, dynamic e, dynamic st) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Error: $e'),
      content: Text('$st'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(
            'Cancel',
          ),
        ),
      ],
    ),
  );
}

class AccountsView extends StatefulWidget {
  const AccountsView({super.key});

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  List<Map> accounts = [];
  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  final emailTextCtrl = TextEditingController();

  int getUsedStorage(Map account) => account['stats']['total']['usedStorage'];

  late List<Map> tiers;

  void _loadAccounts() async {
    final tiersRes = await httpClient.get(
      Uri.parse(
        '$adminApiBaseUrl/accounts/tiers',
      ),
      headers: headers,
    );
    tiers = jsonDecode(tiersRes.body)['tiers'].cast<Map>();

    final res = await httpClient.get(
      Uri.parse(
        '$adminApiBaseUrl/accounts/full',
      ),
      headers: headers,
    );
    accounts = jsonDecode(res.body)['accounts'].cast<Map>();
    accounts.sort(
      (a, b) => -getUsedStorage(a).compareTo(getUsedStorage(b)),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) return LinearProgressIndicator();
    return ListView.builder(
      itemCount: accounts.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Accounts on this node',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Spacer(),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: emailTextCtrl,
                        decoration: InputDecoration(
                          labelText: 'Identifier',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 8,
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          final res = await httpClient.post(
                            Uri.parse(
                              '$adminApiBaseUrl/accounts',
                            ).replace(queryParameters: {
                              'email': emailTextCtrl.text,
                            }),
                            headers: headers,
                          );
                          if (res.statusCode == 200) {
                            final newAccount = {
                              "id": jsonDecode(res.body)['id'],
                              "createdAt":
                                  DateTime.now().millisecondsSinceEpoch,
                              "email": emailTextCtrl.text,
                              "tier": 1,
                              "isRestricted": false,
                              "stats": {
                                "total": {"usedStorage": 0}
                              }
                            };
                            setState(() {
                              accounts.insert(0, newAccount);
                            });
                            emailTextCtrl.clear();
                          } else {
                            throw 'HTTP ${res.statusCode}: ${res.body}';
                          }
                        } catch (e, st) {
                          showErrorDialog(context, e, st);
                        }
                      },
                      child: Text('Create Account'),
                    )
                  ],
                ),
              ),
            ],
          );
        }
        final account = accounts[index - 1];
        final dt = DateTime.fromMillisecondsSinceEpoch(account['createdAt']);
        final bool isRestricted = account['isRestricted'];

        return Container(
          color: index % 2 == 0 ? Color(0xffffffff) : Color(0xff8be9fd),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${account['id']}',
                  textAlign: TextAlign.end,
                ),
              ),
              SizedBox(
                width: 200,
                child: Text(
                  '${account['email']}',
                  textAlign: TextAlign.end,
                ),
              ),
              Tooltip(
                message: dt.toIso8601String(),
                child: SizedBox(
                  width: 100,
                  child: Text(
                    '${(DateTime.now().difference(dt).inHours / 24).toStringAsFixed(1)} days',
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  '${filesize(getUsedStorage(account))}',
                  textAlign: TextAlign.end,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final res = await httpClient.post(
                    Uri.parse(
                      '$adminApiBaseUrl/accounts/set_restricted_status',
                    ).replace(queryParameters: {
                      'id': account['id'].toString(),
                      'status': isRestricted ? 'false' : 'true',
                    }),
                    headers: headers,
                  );
                  if (res.statusCode == 200) {
                    setState(() {
                      account['isRestricted'] = !isRestricted;
                    });
                  }
                },
                child: Text(
                  isRestricted ? 'Unlock' : 'Restrict',
                  style: TextStyle(
                    color: isRestricted ? Colors.red : Colors.green,
                  ),
                ),
              ),
              DropdownButton<int>(
                items: [
                  for (final tier in tiers)
                    DropdownMenuItem(
                      value: tier['id'],
                      child: Text(
                        '${tier['name']} #${tier['id']}',
                      ),
                    )
                ],
                value: account['tier'],
                onChanged: (val) async {
                  final res = await httpClient.post(
                    Uri.parse(
                      '$adminApiBaseUrl/accounts/set_tier',
                    ).replace(queryParameters: {
                      'id': account['id'].toString(),
                      'tier': val.toString(),
                    }),
                    headers: headers,
                  );
                  if (res.statusCode == 200) {
                    setState(() {
                      account['tier'] = val;
                    });
                  }
                },
              ),
              TextButton(
                onPressed: () async {
                  final res = await httpClient.post(
                    Uri.parse(
                      '$adminApiBaseUrl/accounts/new_auth_token',
                    ).replace(queryParameters: {
                      'id': account['id'].toString(),
                    }),
                    headers: headers,
                  );
                  if (res.statusCode == 200) {
                    final authToken = jsonDecode(res.body)['auth_token'];

                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('New Auth Token (copied)'),
                        content: SelectableText(authToken),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Close',
                            ),
                          ),
                        ],
                      ),
                    );
                    Pasteboard.writeText(authToken);
                  }
                },
                child: Text(
                  'Generate Auth Token',
                  style: TextStyle(
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              if (isRestricted)
                TextButton(
                  onPressed: () async {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title:
                            Text('Do you really want to delete this account?'),
                        content:
                            Text('Files will not be deleted. data: $account'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Cancel',
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              final res = await httpClient.delete(
                                Uri.parse(
                                  '$adminApiBaseUrl/accounts',
                                ).replace(queryParameters: {
                                  'id': account['id'].toString(),
                                }),
                                headers: headers,
                              );
                              if (res.statusCode != 200) {
                                throw 'HTTP ${res.statusCode} ${res.body}';
                              }
                              Navigator.of(context).pop();
                              accounts.remove(account);
                              setState(() {});
                            },
                            child: Text(
                              'Delete',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(
                    'Delete account',
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
