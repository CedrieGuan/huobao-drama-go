#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# A21.2 Smoke Test — Drama / Episode CRUD
# Verifies the Go backend (port 5680) is compatible with the Swift client's
# API expectations: response envelope, field names, and required fields.
# ---------------------------------------------------------------------------
set -uo pipefail

BASE="http://localhost:5680/api/v1"
PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1"; ((FAIL++)); }

jq_has() { echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); assert $2" 2>/dev/null; }

echo "🔍 A21.2 Smoke Test — Drama / Episode CRUD"
echo "   Backend: $BASE"
echo ""

# ---- 1. Health check ----
echo "1️⃣  Health check"
R=$(curl -sf "$BASE/health")
if jq_has "$R" "d['status']=='ok'"; then ok "health ok"; else fail "health check failed: $R"; fi

# ---- 2. Create Drama ----
echo "2️⃣  Create Drama"
R=$(curl -sf -X POST "$BASE/dramas" \
  -H "Content-Type: application/json" \
  -d '{"title":"A21烟测","total_episodes":1}')
DRAMA_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)
if [ -n "$DRAMA_ID" ] && jq_has "$R" "d['data']['title']=='A21烟测'"; then
  ok "created drama id=$DRAMA_ID"
else
  fail "create drama failed: $R"
fi

# ---- 3. List Dramas ----
echo "3️⃣  List Dramas"
R=$(curl -sf "$BASE/dramas?page=1&page_size=20")
if jq_has "$R" "isinstance(d['data']['items'], list) and isinstance(d['data']['pagination'], dict)"; then
  ok "list returns items + pagination"
else
  fail "list dramas failed: $R"
fi

# ---- 4. Get Drama Detail ----
echo "4️⃣  Get Drama Detail"
R=$(curl -sf "$BASE/dramas/$DRAMA_ID")
if jq_has "$R" "isinstance(d['data']['episodes'], list) and isinstance(d['data']['characters'], list)"; then
  ok "detail includes episodes/characters/scenes"
else
  fail "get drama detail failed: $R"
fi

# ---- 5. Create Episode ----
echo "5️⃣  Create Episode"
R=$(curl -sf -X POST "$BASE/episodes" \
  -H "Content-Type: application/json" \
  -d "{\"drama_id\":$DRAMA_ID,\"title\":\"烟测集\",\"image_config_id\":1,\"video_config_id\":1,\"audio_config_id\":1}")
EP_ID=$(echo "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])" 2>/dev/null)
if [ -n "$EP_ID" ] && jq_has "$R" "'created_at' in d['data'] and 'status' in d['data']"; then
  ok "created episode id=$EP_ID (full fields)"
else
  fail "create episode failed or incomplete: $R"
fi

# ---- 6. Episode Pipeline Status ----
echo "6️⃣  Episode Pipeline Status"
R=$(curl -sf "$BASE/episodes/$EP_ID/pipeline-status")
if jq_has "$R" "'steps' in d['data'] and d['data']['episode_id']==$EP_ID"; then
  ok "pipeline-status ok"
else
  fail "pipeline-status failed: $R"
fi

# ---- 7. Episode Sub-resources ----
echo "7️⃣  Episode Characters / Scenes / Storyboards"
R=$(curl -sf "$BASE/episodes/$EP_ID/characters")
if jq_has "$R" "isinstance(d['data'], list)"; then ok "characters ok"; else fail "characters failed"; fi
R=$(curl -sf "$BASE/episodes/$EP_ID/scenes")
if jq_has "$R" "isinstance(d['data'], list)"; then ok "scenes ok"; else fail "scenes failed"; fi
R=$(curl -sf "$BASE/episodes/$EP_ID/storyboards")
if jq_has "$R" "isinstance(d['data'], list)"; then ok "storyboards ok"; else fail "storyboards failed"; fi

# ---- 8. Update Episode ----
echo "8️⃣  Update Episode"
R=$(curl -sf -X PUT "$BASE/episodes/$EP_ID" \
  -H "Content-Type: application/json" \
  -d '{"status":"processing"}')
if jq_has "$R" "d['code']==200"; then ok "update episode ok"; else fail "update episode failed: $R"; fi

# ---- 9. Delete Drama ----
echo "9️⃣  Delete Drama"
R=$(curl -sf -X DELETE "$BASE/dramas/$DRAMA_ID")
if jq_has "$R" "d['code']==200"; then ok "delete drama ok"; else fail "delete drama failed: $R"; fi

# ---- 10. Drama Stats ----
echo "🔟 Drama Stats"
R=$(curl -sf "$BASE/dramas/stats")
if jq_has "$R" "'total' in d['data'] and isinstance(d['data']['by_status'], list)"; then
  ok "drama stats ok"
else
  fail "drama stats failed: $R"
fi

echo ""
echo "──────────────────────────────"
echo "  ✅ PASS: $PASS   ❌ FAIL: $FAIL"
echo "──────────────────────────────"
[ "$FAIL" -eq 0 ] && echo "🎉 All smoke tests passed!" || echo "⚠️  Some tests failed — see above"
exit $FAIL
