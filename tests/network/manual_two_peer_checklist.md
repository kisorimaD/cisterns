# Two-peer smoke test

1. Start two game instances built from the same revision.
2. Host on the first instance and join `127.0.0.1` from the second.
3. Mark both players ready and start the match from the host.
4. Confirm each peer controls only its blue local units and sees no hidden enemy coordinates.
5. Check movement, water and gold gathering, bombs, missiles and replacements from both peers.
6. Confirm public strike warnings appear on both peers and reveal zones expose only allowed enemies.
7. Disconnect the client and confirm the host receives a win; repeat with the host disconnecting.
8. Finish a normal match, request a rematch on both peers and confirm both load the same new match.
9. Repeat with artificial latency and packet loss and confirm periodic reliable snapshots converge.
10. On two different machines, choose `Играть через общий сервер`, mark both
    players ready and confirm the match starts through `84.54.47.92:6026/UDP`.
11. Return to the menu, choose `Одиночная игра с ботом` and confirm the bot uses
    movement, strikes and replacements.
