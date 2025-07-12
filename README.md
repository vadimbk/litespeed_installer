# LiteSpeed Enterprise One-Click Installation Script

## Why This Script?

This script was created because the standard `lsws1click.sh` from LiteSpeed Technologies doesn't always work reliably and lacks flexibility for custom port configurations, web port disabling, and other advanced deployment scenarios. This enhanced version provides better error handling, more configuration options, and improved reliability across different server environments.

## Quick Installation

### Basic Setup (5 minutes)
```bash
# Download the script
wget https://raw.githubusercontent.com/vadimbk/litespeed-installer/main/lsws.sh
chmod +x lsws.sh

# Install with SSL certificate for your domain
sudo ./lsws.sh --hostname yourdomain.com --email admin@yourdomain.com

# Access WebAdmin at: https://yourdomain.com:7080
# Credentials will be saved to: /usr/local/lsws/password
```

### Simple Installation Without SSL
```bash
# Install with self-signed certificate
sudo ./lsws.sh

# Access WebAdmin at: https://your-server-ip:7080
```

## Features

- **Reliable Installation**: Enhanced error handling and multi-architecture support (x86_64, ARM64)
- **Flexible Port Configuration**: Custom HTTP, HTTPS, and admin ports
- **Web Port Disabling**: Admin-only mode with `--nowebports`
- **Automatic SSL**: Let's Encrypt certificate generation and auto-renewal
- **PHP Integration**: Multiple PHP versions (7.4-8.4) with customizable extensions
- **Multi-OS Support**: CentOS/RHEL 7-10, Debian 10-12, Ubuntu 18-24
- **SSL-Only Mode**: Generate/renew certificates on existing installations

## Command Line Options

### Essential Options
| Option | Description | Example |
|--------|-------------|---------|
| `--hostname [DOMAIN]` | Domain for SSL certificate | `--hostname example.com` |
| `--email [EMAIL]` | Administrator email | `--email admin@domain.com` |
| `--adminpassword [PASS]` | WebAdmin password | `--adminpassword mypass123` |

### Port Configuration
| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--httpport [PORT]` | HTTP port | 80 | `--httpport 8080` |
| `--httpsport [PORT]` | HTTPS port | 443 | `--httpsport 8443` |
| `--adminport [PORT]` | Admin console port | 7080 | `--adminport 7443` |
| `--nowebports` | Disable HTTP/HTTPS listeners | - | `--nowebports` |

### PHP Configuration
| Option | Description | Values | Example |
|--------|-------------|--------|---------|
| `--lsphp [VERSION]` | PHP version | 74, 80, 81, 82, 83, 84 | `--lsphp 84` |
| `--phpinstall [TYPE]` | Installation type | basic, full | `--phpinstall full` |
| `--phppackages [LIST]` | Custom PHP packages | Space-separated | `--phppackages "mysql gd mbstring"` |

### System Configuration
| Option | Description | Example |
|--------|-------------|---------|
| `--user [USER]` | LiteSpeed run user | `--user www-data` |
| `--group [GROUP]` | LiteSpeed run group | `--group www-data` |
| `--adminuser [USER]` | WebAdmin username | `--adminuser admin` |

### SSL & Control
| Option | Description |
|--------|-------------|
| `--only-ssl` | Only generate/renew SSL certificate |
| `--license [SERIAL]` | Use specific license (default: TRIAL) |
| `-U, --uninstall` | Remove LiteSpeed completely |
| `-Q, --quiet` | No interactive prompts |
| `-v, --verbose` | Detailed output |
| `-H, --help` | Show help |

## Usage Examples

### Web Server with SSL
```bash
# Standard web server with Let's Encrypt SSL
sudo ./lsws.sh --hostname example.com --email admin@example.com --lsphp 84
```

### Admin-Only Server
```bash
# Secure admin-only setup (no web ports)
sudo ./lsws.sh --nowebports --adminport 7443 --hostname admin.example.com
```

### Custom Ports
```bash
# Non-standard ports for development
sudo ./lsws.sh --httpport 8080 --httpsport 8443 --adminport 9080
```

### PHP with Custom Extensions
```bash
# PHP 8.3 with specific extensions
sudo ./lsws.sh --lsphp 83 --phppackages "mysql gd mbstring xml curl"
```

### SSL Certificate Management
```bash
# Add SSL to existing installation
sudo ./lsws.sh --hostname newdomain.com --only-ssl

# Renew existing certificate
sudo ./lsws.sh --hostname example.com --only-ssl
```

## System Requirements

### Supported Operating Systems
- **CentOS/RHEL**: 7, 8, 9, 10+
- **Debian**: 10 (Buster), 11 (Bullseye), 12 (Bookworm)
- **Ubuntu**: 18.04, 20.04, 22.04, 24.04

### Architecture Support
- **x86_64** (Intel/AMD 64-bit)
- **aarch64/arm64** (ARM 64-bit)

### Requirements
- **Virtual Machine or metal server** LiteSpeed Enterprise **doesn't work** in containers!
- **RAM**: 512M Minimum without PHP 
- **Root access** required
- **Internet connection** for downloads and SSL validation

## Important Notes

### User/Group Configuration
- **CentOS/RHEL**: Always uses `nobody:nobody` (system security requirement)
- **Debian/Ubuntu**: Uses `www-data:www-data` by default
- **Custom users**: Automatically validated, falls back to system defaults if invalid

### Port Configuration with `--nowebports`
- Disables HTTP (80) and HTTPS (443) listeners completely
- Only WebAdmin console remains accessible
- Useful for admin-only servers, API gateways, or reverse proxy setups
- SSL certificates can still be generated and managed

### SSL Certificate Behavior
- **With `--hostname`**: Attempts Let's Encrypt certificate, falls back to self-signed
- **Without `--hostname`**: Generates self-signed certificate
- **`--only-ssl` mode**: Requires `--hostname`, only works on existing installations

## PHP Configuration Details

### Available Versions
PHP 7.4, 8.0, 8.1, 8.2, 8.3, 8.4

### Installation Types
- **`basic`**: PHP interpreter only
- **`full`**: Includes common extensions (mysql, gd, mbstring, xml, curl, etc.)
- **Custom**: Use `--phppackages` to specify exact extensions

### PHP Configuration
- **Default settings preserved** - PHP uses standard configuration values
- **Manual configuration** - Adjust settings via WebAdmin console or directly edit php.ini files
- **Configuration location**: 
  - **CentOS/RHEL**: `/usr/local/lsws/lsphp[VERSION]/etc/php.ini`
  - **Debian/Ubuntu**: `/usr/local/lsws/lsphp[VERSION]/etc/php/[X.Y]/litespeed/php.ini` (where X.Y is major.minor PHP version like 8.4)

## Troubleshooting

### Common Issues

**Installation fails:**
```bash
# Check system requirements
df -h && free -m
sudo ./lsws.sh --verbose
```

**SSL certificate generation fails:**
```bash
# Verify DNS points to server
dig yourdomain.com
# Ensure port 80 is open and not blocked by firewall
```

**PHP not working:**
```bash
# Verify PHP installation
ls -la /usr/local/lsws/lsphp*/bin/lsphp
sudo systemctl restart lsws
```

### Log Locations
- **Error log**: `/usr/local/lsws/logs/error.log`
- **Access log**: `/usr/local/lsws/logs/access.log`
- **Admin credentials**: `/usr/local/lsws/password`

### Service Management
```bash
sudo systemctl status lsws
sudo systemctl restart lsws
sudo /usr/local/lsws/bin/lswsctrl restart
```

## SSL Certificate Management

### Let's Encrypt Integration
- Automatic certificate generation via HTTP-01 challenge
- Auto-renewal configured with cron jobs
- Certificates stored in `/etc/letsencrypt/live/[domain]/`

### LiteSpeed-Specific SSL Considerations

**Important**: LiteSpeed requires a proper restart after SSL certificate renewal to pick up new certificates. The script automatically configures this.

**Automatic Renewal Commands**:
```bash
# The script sets up this cron job for proper LiteSpeed restart
0 */12 * * * root certbot -q renew --pre-hook "systemctl stop lsws; /usr/local/lsws/bin/lswsctrl stop" --post-hook "/usr/local/lsws/bin/lswsctrl start; systemctl start lsws"
```

### Manual Certificate Operations
```bash
# Force renewal with LiteSpeed restart
sudo certbot renew --force-renewal --pre-hook "systemctl stop lsws; /usr/local/lsws/bin/lswsctrl stop" --post-hook "/usr/local/lsws/bin/lswsctrl start; systemctl start lsws"

# Using script for renewal (recommended)
sudo ./lsws.sh --hostname yourdomain.com --only-ssl
```

### Wildcard SSL Certificates

For wildcard certificates (`*.domain.com`), you need DNS validation instead of HTTP validation:

**Requirements**:
- DNS provider with API support (Cloudflare, DigitalOcean, GoDaddy, Hetzner, etc.)
- Certbot DNS plugin for your provider
- API credentials from your DNS provider

```

## Uninstallation

```bash
# Interactive removal
sudo ./lsws.sh --uninstall

# Silent removal
sudo ./lsws.sh --uninstall --quiet
```

## LiteSpeed Enterprise License

- **Default**: 15-day trial license
- **Commercial**: Use `--license YOUR_SERIAL_NUMBER`
- **Purchase**: Commercial licenses available at https://store.litespeedtech.com/
- **Manual activation**:
  ```bash
  # Place serial number in file
  echo "YOUR_SERIAL_NUMBER" > /usr/local/lsws/conf/serial.no
  
  # Register license
  sudo /usr/local/lsws/bin/lshttpd -r
  
  # Verify license
  sudo /usr/local/lsws/bin/lshttpd -V
  
  # Restart LiteSpeed
  sudo systemctl restart lsws
  ```

## Contributing

- **Bug reports & feature requests**: Please open an issue in the [GitHub Issues](https://github.com/vadimbk/litespeed-installer/issues) section
- **Pull requests**: Create a feature branch and submit a pull request
- **Testing**: Test on clean OS installations before submitting changes

## Support

- **LiteSpeed Documentation**: https://docs.litespeedtech.com/
- **Community Forum**: https://www.litespeedtech.com/support/forum/
- **GitHub Issues**: For script-specific problems

---

**⚠️ Important**: Always test in non-production environments first. Root privileges required.
