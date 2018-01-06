#!/usr/bin/env python3
import sys
import os.path
import argparse
import re
import pkg_resources

pkg_resources.require('ply')
pkg_resources.require('llvmlite==0.21.*')

import llvmlite.binding as llvm

from util import LocationError, FatalError
from parser import preprocess, parse
from desugar import Desugarer
from context import ContextAnalysis
from typecheck import TypeChecker
from irgen import IRGen


all_phases =[
    'preprocess', 'parser', 'desugar', 'context', 'typecheck', 'irgen'
]


def load_infile(args):
    if not args.infile or args.infile == '-':
        return '<stdin>', sys.stdin.read()

    with open(args.infile) as f:
        return args.infile, f.read()


def infile_basename(args):
    if args.infile:
        return re.sub(r'\.f?[cC]$', '', fname)
    return 'stdin'


def dump(args, prog, phase, print_if_verbose, width=80):
    if args.verbose:
        lfill = rfill = '-' * int((width - len(phase) - 2) / 2)
        if len(phase) % 2:
            rfill += '-'
        print(lfill, phase, rfill, file=sys.stderr)

        if print_if_verbose:
            print(prog, file=sys.stderr)

    if args.dump_after == phase:
        print(prog)
        sys.exit(0)


def save_module(args, module):
    fname = '/dev/stdout' if args.outfile == '-' else args.outfile

    if not fname:
        extension = '.bc' if args.emit_bc else '.ll'
        fname = infile_basename(args) + extension

    mod = llvm.parse_assembly(str(module))
    mod.verify()

    if args.emit_bc:
        with open(fname, 'wb') as f:
            f.write(mod.as_bitcode())
    else:
        with open(fname, 'w') as f:
            f.write(str(mod))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--no-cpp', dest='preprocess', action='store_false',
            help='do not run the preprocessor')
    parser.add_argument('infile', nargs='?', default=None,
            help='input file to compile (default stdin)')
    parser.add_argument('-v', '--verbose', action='store_true',
            help='enable all intermediate dumps and write IR to stdout')
    parser.add_argument('-o', '--outfile', metavar='FILE',
            help='output file (defaults to infile with .ll extension)')
    parser.add_argument('--emit-bc', action='store_true',
            help='write output as bitcode (produces .bc instead of .ll)')
    parser.add_argument('-d', '--dump-after', choices=all_phases,
            help='dump AST/IR to stdout and exit after specified phase')
    parser.add_argument('-I', metavar='PATH', dest='include_paths',
            action='append', default=[],
            help='add include path for preprocessor')
    args = parser.parse_args()

    if args.verbose:
        args.outfile = '-'
        args.emit_ll = True

    if args.outfile is None and args.infile in ('dev/stdin', '-'):
        args.outfile = '-'
        args.emit_ll = True

    # add working dir and parent dir of source file to include path
    args.include_paths.append('.')
    dirname = os.path.dirname(args.infile)
    if dirname:
        args.include_paths.append(dirname)

    try:
        fname, src = load_infile(args)
        origsrc = src

        if args.preprocess:
            src = preprocess(fname, src, args.include_paths)
            dump(args, src, 'preprocess', True)

        tree = parse(fname, src)
        dump(args, tree, 'parser', True)
        tree.verify()

        Desugarer().visit(tree)
        dump(args, tree, 'desugar', True)
        tree.verify()

        ContextAnalysis().visit(tree)
        dump(args, tree, 'context', False)
        tree.verify()

        TypeChecker().visit(tree)
        dump(args, tree, 'typecheck', False)
        tree.verify()

        module = IRGen(infile_basename(args)).visit(tree)
        dump(args, module, 'irgen', False)
        save_module(args, module)

    except EOFError:
        print('Syntax error: unexpected end of file', file=sys.stderr)
        sys.exit(1)
    except LocationError as e:
        e.print(True, origsrc)
        sys.exit(1)
    except (IOError, FatalError) as e:
        print('Error: %s' % e, file=sys.stderr)
        sys.exit(1)
