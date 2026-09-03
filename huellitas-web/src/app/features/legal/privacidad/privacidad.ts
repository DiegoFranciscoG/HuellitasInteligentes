import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-privacidad',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './privacidad.html',
})
/** Política de privacidad — página pública, sin necesidad de sesión. */
export class Privacidad {}
