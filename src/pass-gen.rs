use rand::Rng;

use std::{
    env::{args, var},
    fmt::Display,
    fs::File,
    io::{BufRead, BufReader},
    process::{exit, Command, Stdio},
};

/* -------------------- *
 *        UTILS         *
 * -------------------- */
fn error<T>(msg: T) where T: Display {
    eprintln!("pass-gen: {}", msg);
    exit(1);
}

fn read_wordlist(path: String) -> Vec<String> {
    let file = File::open(path);

    if let Ok(f) = file {
        BufReader::new(f).lines().map(|l| l.unwrap()).collect()
    } else {
        error("file not readable");
        panic!()
    }
}

fn verify_exists(flag: &str, val: Option<&String>) -> String {
    if let Some(str) = val {
        str.clone()
    } else {
        error(format!("missing argument to {}", flag));
        panic!()
    }
}

fn verify_integer(flag: &str, val: String) -> u32 {
    let int = val.parse();

    if matches!(int, Ok(i) if i > 0) {
        int.unwrap()
    } else {
        error(format!("invalid argument to {}, expected integer got '{}'", flag, val));
        panic!()
    }
}


/* -------------------- *
 *        CONFIG        *
 * -------------------- */
#[derive(Debug)]
struct Config {
    word_count: u32,
    word_sep: String,
    word_file: String,
    report: bool,
}


impl Config {
    pub fn new(args: Vec<String>) -> Config {
        let mut config = Config {
            word_count: 6,
            word_sep:   String::from(" "),
            word_file:  format!("{}/.local/lib/pass-gen/wordlist.txt", var("HOME").unwrap()),
            report:     false,
        };

        let mut i = 1;
        while args.len() > i {
            let flag = args[i].as_str();
            i += 1;

            match flag {
                "-w" | "--word" => {
                    let val = verify_exists(flag, args.get(i));

                    config.word_count = verify_integer(flag, val);
                    i += 1;
                }
                "-s" | "--sep" => {
                    let val = verify_exists(flag, args.get(i));

                    config.word_sep = val;
                    i += 1;
                }
                "-f" | "--file" => {
                    let val = verify_exists(flag, args.get(i));

                    config.word_file = val;
                    i += 1;
                }
                "-r" | "--report" => {
                    config.report = true;
                }
                "-h" | "--help" => Config::print_help(),
                _ => error(format!("invalid option {}", flag)),
            }
        }

        config
    }

    fn print_help() {
        println!(
"Usage: pass-gen-rust [OPTIONS]

Options:
  -w, --word N        generate password of N words
  -s, --sep STRING    set STRING as the word separator
  -f, --file PATH     set PATH as the wordlist
  -r, --report        print report of password strength
  -h, --help          display this help and exit

Examples:
  pass-gen -w 8 -s '-'
  pass-gen -r");

        exit(0);
    }
}


/* -------------------- *
 *        REPORT        *
 * -------------------- */
fn get_cols() -> u16 {
    let res = Command::new("tput")
        .arg("cols")
        .stderr(Stdio::inherit())
        .output();

    if let Ok(mut output) = res {
        output.stdout.pop();
        String::from_utf8(output.stdout).unwrap().parse().unwrap()
    } else {
        60
    }
}

fn tounit(x: f64, unit: &str) -> String {
    if x < 1e9 {
        format!("{:.0} {}", x, unit)
    } else {
        format!("{} {}", format!("{:.0e}", x).replace("e", "e+"), unit)
    }
}

fn format_time(t: f64) -> String {
    let minute  = 60.0;
    let hour    = minute * 60.0;
    let day     = hour * 24.0;
    let year    = day * 365.25;
    let century = year * 100.0;

    if t < 1.0 {
        String::from("less than a second")
    } else if t < minute {
        tounit(t, "seconds")
    } else if t < hour {
        tounit(t / minute, "minutes")
    } else if t < day {
        tounit(t / hour, "hours")
    } else if t < year {
        tounit(t / day, "days")
    } else if t < century {
        tounit(t / year, "years")
    } else {
        tounit(t / century, "centuries")
    }
}

fn print_report(pool: f64, count: u32) {
    let entropy = pool.log2();
    let total_entropy = entropy * count as f64;

    eprintln!("entropy per word:           {:.1} bits", entropy);
    eprintln!("total entropy:              {:.0} bits", total_entropy);
    eprintln!("guess times:");
    eprintln!("  1 quadrillion / second:   {}", format_time((total_entropy - 51.0).exp2()));
    eprintln!("  1 quintillion / second:   {}", format_time((total_entropy - 61.0).exp2()));
    eprintln!("  1 sextillion / second:    {}", format_time((total_entropy - 71.0).exp2()));

    let cols = get_cols();
    let mut i = 0;
    while i < cols {
        eprint!("-");
        i += 1;
    }
    eprint!("\n");
}


/* -------------------- *
 *         MAIN         *
 * -------------------- */
fn main() {
    let config = Config::new(args().collect());
    let words = read_wordlist(config.word_file);
    let len = words.len();

    if config.report {
        print_report(len as f64, config.word_count)
    }

    let mut rng = rand::thread_rng();
    let mut i = 0;
    while i < config.word_count {
        print!("{}", words[rng.gen_range(0..len)]);

        i += 1;

        if i != config.word_count {
            print!("{}", config.word_sep)
        };
    }
}
