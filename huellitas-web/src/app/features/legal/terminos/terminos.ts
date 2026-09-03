import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-terminos',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './terminos.html',
})
/** Términos de uso — página pública, sin necesidad de sesión. */
export class Terminos {}
