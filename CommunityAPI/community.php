<?php
/*
 * mSign Community v2 endpoint.
 *
 * IMPORTANT: wire community_auth() to the authentication helper already used
 * by account.php. Do not create a second independent token system.
 */
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
require __DIR__ . '/_db.php';

function out($x, int $code=200): never { http_response_code($code); echo json_encode($x, JSON_UNESCAPED_SLASHES); exit; }
function input_json(): array { $v=json_decode(file_get_contents('php://input'),true); return is_array($v)?$v:$_POST; }
function community_auth(PDO $pdo): array {
    /* Replace this block with the existing account.php bearer-token validator. */
    $token = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (preg_match('/^Bearer\s+(.+)$/i',$token,$m)) $token=$m[1];
    $token = $token ?: ($_GET['token'] ?? ($_POST['token'] ?? ''));
    if (!$token) out(['ok'=>false,'error'=>'Authentication required'],401);

    // If your account.php already exposes an auth helper, call it here.
    // This fallback supports a deployments table named api_sessions only.
    try {
        $q=$pdo->prepare('SELECT user_id FROM api_sessions WHERE token_hash=? AND (expires_at IS NULL OR expires_at>NOW()) LIMIT 1');
        $q->execute([hash('sha256',$token)]);
        $uid=$q->fetchColumn();
    } catch(Throwable $e) { $uid=false; }
    if (!$uid) out(['ok'=>false,'error'=>'Invalid session'],401);
    $q=$pdo->prepare('SELECT id,username,role FROM users WHERE id=? LIMIT 1'); $q->execute([$uid]); $u=$q->fetch(PDO::FETCH_ASSOC);
    if (!$u) out(['ok'=>false,'error'=>'Account not found'],401);
    return $u;
}
function roleRank(string $r): int { return ['member'=>0,'developer'=>1,'admin'=>2][$r] ?? 0; }

$pdo=db(); $me=community_auth($pdo); $method=$_SERVER['REQUEST_METHOD'];
$action=$_GET['action'] ?? '';
$body=$method==='POST'?input_json():[];
if ($method==='POST') $action=$body['action'] ?? $action;

if ($action==='announcements' && $method==='GET') {
    $sql="SELECT a.id,a.title,a.body,a.audience,a.created_at,a.expires_at,
                 u.username sender_username,u.role sender_role,
                 CASE WHEN r.user_id IS NULL THEN 0 ELSE 1 END AS is_read
          FROM community_announcements a
          JOIN users u ON u.id=a.sender_id
          LEFT JOIN community_announcement_reads r ON r.announcement_id=a.id AND r.user_id=?
          WHERE (a.expires_at IS NULL OR a.expires_at>NOW())
            AND (a.audience='everyone'
              OR (a.audience='staff' AND u.role IN ('developer','admin'))
              OR (a.audience='developer' AND ? IN ('developer','admin'))
              OR (a.audience='admin' AND ?='admin')
              OR (a.audience='individual' AND a.target_user_id=?))
          ORDER BY a.created_at DESC LIMIT 100";
    $q=$pdo->prepare($sql); $q->execute([$me['id'],$me['role'],$me['role'],$me['id']]);
    $rows=[]; foreach($q as $r){$r['id']=(string)$r['id'];$r['read']=(bool)$r['is_read'];unset($r['is_read']);$rows[]=$r;}
    out(['ok'=>true,'announcements'=>$rows]);
}

if ($action==='announcement_read' && $method==='POST') {
    $id=(int)($body['announcement_id']??0); if($id<1) out(['ok'=>false,'error'=>'Bad announcement'],400);
    $q=$pdo->prepare('INSERT IGNORE INTO community_announcement_reads(announcement_id,user_id) VALUES(?,?)');$q->execute([$id,$me['id']]);
    out(['ok'=>true]);
}

if ($action==='announcement_create' && $method==='POST') {
    if(roleRank($me['role'])<1) out(['ok'=>false,'error'=>'Developer or admin role required'],403);
    $aud=$body['audience']??''; $allowed=['everyone','staff','developer','admin','individual'];
    if(!in_array($aud,$allowed,true)) out(['ok'=>false,'error'=>'Invalid audience'],400);
    $title=trim((string)($body['title']??''));$text=trim((string)($body['body']??''));
    if($title===''||$text==='') out(['ok'=>false,'error'=>'Title and body are required'],400);
    $target=null;
    if($aud==='individual'){
        $uname=trim((string)($body['target']??'')); if($uname==='') out(['ok'=>false,'error'=>'Target username required'],400);
        $q=$pdo->prepare('SELECT id FROM users WHERE username=? LIMIT 1');$q->execute([$uname]);$target=$q->fetchColumn();
        if(!$target) out(['ok'=>false,'error'=>'Target user not found'],404);
    }
    $expires=null;if(!empty($body['expires_at'])){$ts=strtotime((string)$body['expires_at']);if($ts===false)out(['ok'=>false,'error'=>'Invalid expiration'],400);$expires=date('Y-m-d H:i:s',$ts);}
    $q=$pdo->prepare('INSERT INTO community_announcements(sender_id,audience,target_user_id,title,body,expires_at) VALUES(?,?,?,?,?,?)');$q->execute([$me['id'],$aud,$target,$title,$text,$expires]);
    $id=(int)$pdo->lastInsertId();
    $q=$pdo->prepare('INSERT INTO community_audit(actor_id,action,target) VALUES(?,?,?)');$q->execute([$me['id'],'announcement.create',$aud==='individual'?(string)$target:$aud]);
    out(['ok'=>true,'id'=>(string)$id]);
}

if ($action==='audit' && $method==='GET') {
    if($me['role']!=='admin') out(['ok'=>false,'error'=>'Admin role required'],403);
    $q=$pdo->query("SELECT a.id,a.action,a.target,a.created_at,u.username actor_username,u.role actor_role FROM community_audit a JOIN users u ON u.id=a.actor_id ORDER BY a.created_at DESC LIMIT 200");
    $rows=[];foreach($q as $r){$r['id']=(string)$r['id'];$rows[]=$r;} out(['ok'=>true,'events'=>$rows]);
}

out(['ok'=>false,'error'=>'Unknown action'],404);
