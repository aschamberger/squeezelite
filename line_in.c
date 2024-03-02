/*
 *  Squeezelite - lightweight headless squeezebox emulator
 *
 *  (c) Adrian Smith 2012-2015, triode1@btinternet.com
 *      Ralph Irving 2015-2024, ralph_irving@hotmail.com
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * gpio.c (c) Paul Hermann, 2015-2024 under the same license terms
 *   -Control of Raspberry pi GPIO for amplifier power
 *   -Launch script on power status change from LMS
 */

#if LINE_IN

#include "squeezelite.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Holds current status to avoid starting line in script multiple times
static int line_in_state = -1;

char *cmdline;
int argloc;

void line_in_script(int state, int volume) {
    int err;

    if (cmdline == NULL){
        argloc = strlen(line_in_script);
        cmdline = (char*) malloc(argloc+2+4+1);
        strcpy(cmdline, line_in_script);
    }

    // set volume level
    if (state == 2){
        if( (volume >= 0) && (volume <= 100)){
            sprintf(cmdline + argloc, " 2 %d", volume);
            if ((err = system(cmdline)) != 0){
                fprintf (stderr, "%s exit status = %d\n", cmdline, err);
            }
        }
        else {
            fprintf (stderr, "invalid volume level given = %i\n", volume);
        }
    }
    // turn on line in
    else if( (state == 1) && (line_in_state != 1)){
        strcat(cmdline + argloc, " 1");
        if ((err = system(cmdline)) != 0){
            fprintf (stderr, "%s exit status = %d\n", cmdline, err);
        }
        else {
            line_in_state = 1;
        }
    }
    // turn off line in
    else if( (state == 0) && (line_in_state != 0)){
        strcat(cmdline + argloc, " 0");
        if ((err = system(cmdline)) != 0){
            fprintf (stderr, "%s exit status = %d\n", cmdline, err);
        }
        else {
            line_in_state = 0;
        }
    }
}

#endif // LINE_IN