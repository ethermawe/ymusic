#[cfg(unix)]
use std::ffi::{CStr, CString};
use std::net::SocketAddr;
#[cfg(unix)]
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket};
#[cfg(unix)]
use std::sync::OnceLock;

use reqwest::dns::{Addrs, Name, Resolve, Resolving};

/// Резолвер, который не ждёт AAAA-записи на машинах без IPv6.
///
/// Системный `getaddrinfo` с `AF_UNSPEC` при недоступном IPv6 иногда висит 5–15 с
/// на таймаутах DNS, а соединяться по IPv6 всё равно некуда.
pub struct Resolver;

impl Resolve for Resolver {
    fn resolve(&self, name: Name) -> Resolving {
        let host = name.as_str().to_string();
        Box::pin(async move {
            let addrs = tokio::task::spawn_blocking(move || lookup(&host)).await??;
            Ok(Box::new(addrs.into_iter()) as Addrs)
        })
    }
}

#[cfg(unix)]
fn has_ipv6() -> bool {
    static CACHE: OnceLock<bool> = OnceLock::new();
    // connect() у UDP не шлёт пакетов, только проверяет наличие маршрута
    *CACHE.get_or_init(|| {
        UdpSocket::bind((Ipv6Addr::UNSPECIFIED, 0))
            .and_then(|s| s.connect((Ipv6Addr::new(0x2001, 0x4860, 0, 0, 0, 0, 0, 0x8888), 53)))
            .is_ok()
    })
}

#[cfg(unix)]
fn lookup(host: &str) -> std::io::Result<Vec<SocketAddr>> {
    let family = if has_ipv6() {
        libc::AF_UNSPEC
    } else {
        libc::AF_INET
    };
    let mut addrs = getaddrinfo(host, family)?;
    // IPv4 первым: он работает почти везде, IPv6 остаётся запасным
    addrs.sort_by_key(|a| a.is_ipv6());
    Ok(addrs)
}

#[cfg(not(unix))]
fn lookup(host: &str) -> std::io::Result<Vec<SocketAddr>> {
    use std::net::ToSocketAddrs;
    let mut addrs: Vec<SocketAddr> = (host, 0).to_socket_addrs()?.collect();
    addrs.sort_by_key(|a| a.is_ipv6());
    Ok(addrs)
}

#[cfg(unix)]
fn getaddrinfo(host: &str, family: libc::c_int) -> std::io::Result<Vec<SocketAddr>> {
    let c_host = CString::new(host).map_err(|_| std::io::Error::other("некорректное имя хоста"))?;
    // SAFETY: обнулённая addrinfo — корректные «подсказки» для getaddrinfo
    let mut hints: libc::addrinfo = unsafe { std::mem::zeroed() };
    hints.ai_family = family;
    hints.ai_socktype = libc::SOCK_STREAM;

    let mut res: *mut libc::addrinfo = std::ptr::null_mut();
    // SAFETY: указатели валидны на время вызова, результат освобождается ниже
    let rc = unsafe { libc::getaddrinfo(c_host.as_ptr(), std::ptr::null(), &hints, &mut res) };
    if rc != 0 {
        // SAFETY: gai_strerror возвращает статическую строку
        let msg = unsafe { CStr::from_ptr(libc::gai_strerror(rc)) };
        return Err(std::io::Error::other(format!(
            "не удалось найти {host}: {}",
            msg.to_string_lossy()
        )));
    }

    let mut out = Vec::new();
    let mut cur = res;
    while !cur.is_null() {
        // SAFETY: cur — элемент списка, который вернул getaddrinfo
        let ai = unsafe { &*cur };
        if !ai.ai_addr.is_null() {
            match ai.ai_family {
                libc::AF_INET => {
                    // SAFETY: для AF_INET ai_addr указывает на sockaddr_in
                    let sa = unsafe { &*(ai.ai_addr as *const libc::sockaddr_in) };
                    let ip = Ipv4Addr::from(u32::from_be(sa.sin_addr.s_addr));
                    out.push(SocketAddr::new(IpAddr::V4(ip), 0));
                }
                libc::AF_INET6 => {
                    // SAFETY: для AF_INET6 ai_addr указывает на sockaddr_in6
                    let sa = unsafe { &*(ai.ai_addr as *const libc::sockaddr_in6) };
                    let ip = Ipv6Addr::from(sa.sin6_addr.s6_addr);
                    out.push(SocketAddr::new(IpAddr::V6(ip), 0));
                }
                _ => {}
            }
        }
        cur = ai.ai_next;
    }
    // SAFETY: res получен от успешного getaddrinfo
    unsafe { libc::freeaddrinfo(res) };
    out.dedup();
    Ok(out)
}
